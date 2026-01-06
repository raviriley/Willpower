//
//  IPCManager.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation
import os.log

private let logger = WillpowerLogger.ipc

// MARK: - Role Enum

/// Role identifier for IPC participants
public enum IPCRole: String, Sendable {
    case app
    case daemon
}

/// Manages IPC between Willpower app and daemon
/// Uses file-based IPC at /Library/Application Support/Willpower/ipc/
/// with role-based permissions (admin group only)
///
/// Note: App Groups were removed because macOS macl (Mandatory Access Control Label)
/// blocks root daemon access to user's App Groups container.
/// TODO: Replace with XPC for more secure communication in a future release.
///
/// Thread Safety: Marked `@unchecked Sendable` because thread safety is guaranteed by:
/// - Immutable properties after initialization (encoder, decoder, role)
/// - FileManager operations are thread-safe
/// - File-level locking for state modifications (see `queueCommand`)
/// - No shared mutable state between method calls
public final class IPCManager: @unchecked Sendable {

    // MARK: - Constants

    /// IPC subdirectory name
    private static let ipcSubdirectory = "ipc"

    /// Admin group ID for file ownership (used by daemon)
    private static let adminGroupID: UInt32 = 80  // 'admin' group on macOS

    // MARK: - IPC Paths (Computed)

    /// Base IPC directory
    ///
    /// Uses /Library/Application Support/Willpower/ipc/ which is accessible
    /// by both root (daemon) and user (app) processes.
    ///
    /// Security: Files are restricted to root:admin group with 0o640/0o660 permissions
    public static var ipcDirectory: String {
        return "/Library/Application Support/Willpower/\(ipcSubdirectory)"
    }

    public static var stateFile: String { ipcDirectory + "/state.json" }
    public static var stateBackupFile: String { ipcDirectory + "/state.json.backup" }
    public static var commandsFile: String { ipcDirectory + "/commands.json" }
    public static var heartbeatFile: String { ipcDirectory + "/heartbeat" }

    // MARK: - Properties

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager = FileManager.default
    private let role: IPCRole

    /// Whether IPC is available (directory exists or can be created)
    public var isAvailable: Bool {
        return fileManager.fileExists(atPath: Self.ipcDirectory) ||
               fileManager.isWritableFile(atPath: "/Library/Application Support/Willpower")
    }

    // MARK: - Initialization

    /// Initialize IPCManager with specified role
    /// - Parameter role: The role of this process (.app or .daemon)
    public init(role: IPCRole = .app) {
        self.role = role
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        // Use ISO8601 date encoding for consistency
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // Ensure IPC directory exists
        ensureIPCDirectory()
    }

    /// Ensure the IPC directory exists with appropriate permissions
    /// Uses /Library/Application Support which both root and user can access
    /// Permissions: root:admin ownership, 0o750 (parent) / 0o770 (ipc dir)
    private func ensureIPCDirectory() {
        let path = Self.ipcDirectory

        // Also ensure parent directory exists
        let parentPath = "/Library/Application Support/Willpower"
        if !fileManager.fileExists(atPath: parentPath) {
            try? fileManager.createDirectory(atPath: parentPath, withIntermediateDirectories: true)
            // 0o750: owner (root) rwx, group (admin) r-x, others ---
            try? fileManager.setAttributes([.posixPermissions: 0o750], ofItemAtPath: parentPath)
            // Set group to admin if we're running as daemon (root)
            if role == .daemon {
                try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: parentPath)
            }
        }

        if !fileManager.fileExists(atPath: path) {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            // 0o770: owner (root) rwx, group (admin) rwx, others ---
            // Group needs write for app to create/modify commands.json
            try? fileManager.setAttributes([.posixPermissions: 0o770], ofItemAtPath: path)
            // Set group to admin if we're running as daemon (root)
            if role == .daemon {
                try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: path)
            }
            logger.info("Created IPC directory: \(path)")
        }
    }

    // MARK: - State Management

    /// Save the current Willpower state (typically called by daemon)
    /// - Parameters:
    ///   - state: The state to save
    ///   - backupFirst: If true, backs up current state before writing. Use for configuration changes
    ///                  (blocklist/trigger create/update/delete) to ensure recovery is possible.
    public func saveState(_ state: WillpowerState, backupFirst: Bool = false) throws {
        let data = try encoder.encode(state)

        ensureIPCDirectory()

        // Only backup when configuration changes (not on every heartbeat/runtime update)
        if backupFirst {
            backupCurrentState()
        }

        let url = URL(fileURLWithPath: Self.stateFile)
        try data.write(to: url, options: .atomic)
        // 0o640: owner (root) rw-, group (admin) r--, others ---
        // Daemon writes, app (in admin group) reads
        try? fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: Self.stateFile)
        if role == .daemon {
            try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.stateFile)
        }
    }

    /// Backup current state.json to state.json.backup
    /// Called before configuration changes to ensure blocklist/trigger configs are never lost
    private func backupCurrentState() {
        guard fileManager.fileExists(atPath: Self.stateFile) else { return }

        do {
            // Remove old backup if it exists
            if fileManager.fileExists(atPath: Self.stateBackupFile) {
                try fileManager.removeItem(atPath: Self.stateBackupFile)
            }
            // Copy current state to backup
            try fileManager.copyItem(atPath: Self.stateFile, toPath: Self.stateBackupFile)
            // Set same permissions on backup
            try? fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: Self.stateBackupFile)
            if role == .daemon {
                try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.stateBackupFile)
            }
        } catch {
            logger.warning("Failed to backup state: \(error.localizedDescription)")
        }
    }

    /// Load the current Willpower state
    /// Falls back to backup file if main state file is corrupted
    public func loadState() throws -> WillpowerState? {
        // Try loading main state file
        if let state = try? loadStateFromFile(Self.stateFile) {
            return state
        }

        // Main file failed, try backup
        if fileManager.fileExists(atPath: Self.stateBackupFile) {
            logger.warning("Main state file corrupted or missing, attempting recovery from backup")
            if let backupState = try? loadStateFromFile(Self.stateBackupFile) {
                logger.info("Successfully recovered state from backup")
                // Restore backup to main file
                try? restoreFromBackup()
                return backupState
            }
            logger.error("Backup file also corrupted, state recovery failed")
        }

        return nil
    }

    /// Load state from a specific file path
    private func loadStateFromFile(_ path: String) throws -> WillpowerState? {
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try decoder.decode(WillpowerState.self, from: data)
    }

    /// Restore state.json from backup file
    private func restoreFromBackup() throws {
        guard fileManager.fileExists(atPath: Self.stateBackupFile) else { return }

        // Remove corrupted main file
        if fileManager.fileExists(atPath: Self.stateFile) {
            try fileManager.removeItem(atPath: Self.stateFile)
        }
        // Copy backup to main
        try fileManager.copyItem(atPath: Self.stateBackupFile, toPath: Self.stateFile)
        // Set permissions
        try? fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: Self.stateFile)
        if role == .daemon {
            try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.stateFile)
        }
        logger.info("Restored state.json from backup")
    }

    /// Load state or return a default empty state
    /// Attempts recovery from backup before falling back to default
    public func loadStateOrDefault() -> WillpowerState {
        do {
            return try loadState() ?? WillpowerState()
        } catch {
            logger.error("Error loading state: \(error.localizedDescription). Returning default.")
            return WillpowerState()
        }
    }

    // MARK: - Commands (App -> Daemon)

    /// Queue a command for the daemon to process
    public func queueCommand(_ command: DaemonCommand) throws {
        // Load existing commands
        var commands = (try? loadPendingCommands()) ?? []

        // DEDUPLICATION: For updateBlocklists, remove any existing updateBlocklists commands
        // since we only care about the latest blocklist state
        if case .updateBlocklists = command {
            let beforeCount = commands.count
            commands.removeAll { wrapper in
                if case .updateBlocklists = wrapper.command { return true }
                return false
            }
            if beforeCount != commands.count {
                logger.debug("Deduplicated \(beforeCount - commands.count) stale updateBlocklists command(s)")
            }
        }

        // DEDUPLICATION: For updateIndependentTriggers, remove any existing commands
        if case .updateIndependentTriggers = command {
            let beforeCount = commands.count
            commands.removeAll { wrapper in
                if case .updateIndependentTriggers = wrapper.command { return true }
                return false
            }
            if beforeCount != commands.count {
                logger.debug("Deduplicated \(beforeCount - commands.count) stale updateIndependentTriggers command(s)")
            }
        }

        // Add new command with wrapper
        let wrapper = CommandWrapper(command: command)
        commands.append(wrapper)

        // Save to file
        let data = try encoder.encode(commands)
        ensureIPCDirectory()
        let url = URL(fileURLWithPath: Self.commandsFile)
        try data.write(to: url, options: .atomic)
        // 0o660: owner (root) rw-, group (admin) rw-, others ---
        // Both daemon and app (in admin group) need read/write
        try? fileManager.setAttributes([.posixPermissions: 0o660], ofItemAtPath: Self.commandsFile)
        if role == .daemon {
            try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.commandsFile)
        }
    }

    /// Load pending commands (called by daemon)
    public func loadPendingCommands() throws -> [CommandWrapper] {
        let url = URL(fileURLWithPath: Self.commandsFile)
        if fileManager.fileExists(atPath: Self.commandsFile),
           let data = try? Data(contentsOf: url) {
            return try decoder.decode([CommandWrapper].self, from: data)
        }
        return []
    }

    /// Clear all pending commands (called by daemon after processing)
    public func clearPendingCommands() throws {
        try? fileManager.removeItem(atPath: Self.commandsFile)
    }

    /// Mark a specific command as processed by removing it
    public func markCommandProcessed(_ commandId: UUID) throws {
        var commands = try loadPendingCommands()
        commands.removeAll { $0.id == commandId }

        if commands.isEmpty {
            try? fileManager.removeItem(atPath: Self.commandsFile)
        } else {
            let data = try encoder.encode(commands)
            let url = URL(fileURLWithPath: Self.commandsFile)
            try data.write(to: url, options: .atomic)
            // 0o660 permissions
            try? fileManager.setAttributes([.posixPermissions: 0o660], ofItemAtPath: Self.commandsFile)
            if role == .daemon {
                try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.commandsFile)
            }
        }
    }

    // MARK: - Daemon Heartbeat

    /// Update daemon heartbeat (called periodically by daemon)
    public func updateDaemonHeartbeat() {
        let timestamp = Date().timeIntervalSince1970

        ensureIPCDirectory()
        let timestampString = String(timestamp)
        try? timestampString.write(toFile: Self.heartbeatFile, atomically: true, encoding: .utf8)
        // 0o640: owner (root) rw-, group (admin) r--, others ---
        // Daemon writes, app (in admin group) reads
        try? fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: Self.heartbeatFile)
        if role == .daemon {
            try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.heartbeatFile)
        }
    }

    /// Check if daemon is alive (heartbeat within threshold)
    public func isDaemonAlive(threshold: TimeInterval = 15.0) -> Bool {
        if fileManager.fileExists(atPath: Self.heartbeatFile),
           let contents = try? String(contentsOfFile: Self.heartbeatFile, encoding: .utf8),
           let timestamp = TimeInterval(contents) {
            return Date().timeIntervalSince1970 - timestamp < threshold
        }
        return false
    }

    /// Get last daemon heartbeat time
    public func lastDaemonHeartbeat() -> Date? {
        if fileManager.fileExists(atPath: Self.heartbeatFile),
           let contents = try? String(contentsOfFile: Self.heartbeatFile, encoding: .utf8),
           let timestamp = TimeInterval(contents) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    /// Get seconds since last heartbeat (nil if never)
    public func secondsSinceLastHeartbeat() -> TimeInterval? {
        guard let lastHeartbeat = lastDaemonHeartbeat() else {
            return nil
        }
        return Date().timeIntervalSince(lastHeartbeat)
    }

    // MARK: - Convenience Methods

    /// Send an activate command for a blocklist
    public func activateBlocklist(
        _ blocklistId: UUID,
        trigger: TriggerConfig? = nil,
        isLocked: Bool = true
    ) throws {
        try queueCommand(.activateBlocklist(blocklistId: blocklistId, trigger: trigger, isLocked: isLocked))
    }

    /// Send a deactivate command for a blocklist
    public func deactivateBlocklist(_ blocklistId: UUID) throws {
        try queueCommand(.deactivateBlocklist(blocklistId: blocklistId))
    }

    /// Send updated blocklist configurations to daemon
    public func updateBlocklists(_ blocklists: [BlocklistConfig]) throws {
        try queueCommand(.updateBlocklists(blocklists))
    }

    /// Request a state sync from daemon
    public func requestSync() throws {
        try queueCommand(.forceSync)
    }

    /// Report a URL visit (called by app which runs BrowserMonitor)
    public func reportVisit(patternId: UUID, url: String) throws {
        try queueCommand(.reportVisit(patternId: patternId, url: url))
    }

    /// Send updated independent triggers to daemon
    public func updateIndependentTriggers(_ triggers: [IndependentTrigger]) throws {
        try queueCommand(.updateIndependentTriggers(triggers))
    }

    /// Delete a specific independent trigger
    public func deleteIndependentTrigger(triggerId: UUID) throws {
        try queueCommand(.deleteIndependentTrigger(triggerId: triggerId))
    }

    // MARK: - Debug

    /// Get debug description of current IPC state
    public func debugDescription() -> String {
        var lines: [String] = []
        lines.append("=== IPCManager Debug Info ===")
        lines.append("IPC Directory: \(Self.ipcDirectory)")
        lines.append("Available: \(isAvailable)")
        lines.append("Backup exists: \(fileManager.fileExists(atPath: Self.stateBackupFile))")

        if let heartbeat = lastDaemonHeartbeat() {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            lines.append("Last Heartbeat: \(formatter.string(from: heartbeat))")
            lines.append("Daemon Alive: \(isDaemonAlive())")
        } else {
            lines.append("Last Heartbeat: Never")
            lines.append("Daemon Alive: false")
        }

        if let commands = try? loadPendingCommands() {
            lines.append("Pending Commands: \(commands.count)")
        }

        if let state = try? loadState() {
            lines.append("Blocklists: \(state.blocklists.count)")
            lines.append("Active Blocks: \(state.activeBlocks.count)")
            lines.append("Visit Records: \(state.visitRecords.count)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

extension IPCManager {
    public enum IPCError: Error, LocalizedError {
        case ipcUnavailable
        case encodingFailed(underlying: Error)
        case decodingFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .ipcUnavailable:
                return "IPC not available. Ensure daemon has created the IPC directory."
            case .encodingFailed(let e):
                return "Failed to encode data: \(e.localizedDescription)"
            case .decodingFailed(let e):
                return "Failed to decode data: \(e.localizedDescription)"
            }
        }
    }
}
