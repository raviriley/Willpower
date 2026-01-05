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
/// Uses file-based IPC with tighter permissions (admin group only)
/// Falls back to UserDefaults if available
public final class IPCManager: @unchecked Sendable {

    // MARK: - Constants

    /// App Group identifier - must match in both app and daemon entitlements
    public static let appGroupIdentifier = "group.P5AM8FWTFW.raviriley.Willpower"

    /// IPC subdirectory within App Groups container
    private static let ipcSubdirectory = "ipc"

    /// Admin group ID for file ownership (used by daemon)
    private static let adminGroupID: UInt32 = 80  // 'admin' group on macOS

    // MARK: - IPC Paths (Computed)

    /// Base IPC directory - computed based on context (app vs daemon)
    ///
    /// NOTE: We use /Library/Application Support/Willpower for IPC because:
    /// - App Groups containers have macOS macl (Mandatory Access Control Label) that blocks root access
    /// - The daemon runs as root and cannot write to user's App Groups container
    /// - Even with the App Groups entitlement, macl also checks UID (root != user)
    /// - /Library/Application Support is accessible by both root and user processes
    ///
    /// Security: Files are restricted to root:admin group with 0o640/0o660 permissions
    /// TODO: Replace with XPC for more secure communication
    public static var ipcDirectory: String {
        // Use a system-wide location that both root (daemon) and user (app) can access
        return "/Library/Application Support/Willpower/\(ipcSubdirectory)"
    }

    public static var stateFile: String { ipcDirectory + "/state.json" }
    public static var commandsFile: String { ipcDirectory + "/commands.json" }
    public static var heartbeatFile: String { ipcDirectory + "/heartbeat" }

    /// Keys for UserDefaults storage (fallback)
    private enum Keys {
        static let state = "willpower.state"
        static let commands = "willpower.commands"
        static let daemonHeartbeat = "willpower.daemon.heartbeat"
        static let appVersion = "willpower.app.version"
    }

    // MARK: - Properties

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager = FileManager.default
    private let role: IPCRole

    /// Whether App Groups access is available
    public var isAvailable: Bool {
        return defaults != nil || fileManager.isWritableFile(atPath: Self.ipcDirectory)
    }

    // MARK: - Initialization

    /// Initialize IPCManager with specified role
    /// - Parameter role: The role of this process (.app or .daemon)
    public init(role: IPCRole = .app) {
        self.role = role
        self.defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        // Use ISO8601 date encoding for consistency
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // Ensure IPC directory exists
        ensureIPCDirectory()

        if defaults == nil {
            logger.info("App Group UserDefaults not available, using file-based IPC")
        }
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
    public func saveState(_ state: WillpowerState) throws {
        let data = try encoder.encode(state)

        // Primary: file-based
        ensureIPCDirectory()
        let url = URL(fileURLWithPath: Self.stateFile)
        try data.write(to: url, options: .atomic)
        // 0o640: owner (root) rw-, group (admin) r--, others ---
        // Daemon writes, app (in admin group) reads
        try? fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: Self.stateFile)
        if role == .daemon {
            try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.stateFile)
        }

        // Fallback: also save to UserDefaults if available
        defaults?.set(data, forKey: Keys.state)
        defaults?.synchronize()
    }

    /// Load the current Willpower state
    public func loadState() throws -> WillpowerState? {
        // Primary: try file-based first
        let url = URL(fileURLWithPath: Self.stateFile)
        if fileManager.fileExists(atPath: Self.stateFile),
           let data = try? Data(contentsOf: url) {
            return try decoder.decode(WillpowerState.self, from: data)
        }

        // Fallback: try UserDefaults
        if let defaults, let data = defaults.data(forKey: Keys.state) {
            return try decoder.decode(WillpowerState.self, from: data)
        }

        return nil
    }

    /// Load state or return a default empty state
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

        // Also save to UserDefaults if available
        defaults?.set(data, forKey: Keys.commands)
        defaults?.synchronize()
    }

    /// Load pending commands (called by daemon)
    public func loadPendingCommands() throws -> [CommandWrapper] {
        // Primary: try file-based first
        let url = URL(fileURLWithPath: Self.commandsFile)
        if fileManager.fileExists(atPath: Self.commandsFile),
           let data = try? Data(contentsOf: url) {
            return try decoder.decode([CommandWrapper].self, from: data)
        }

        // Fallback: try UserDefaults
        if let defaults, let data = defaults.data(forKey: Keys.commands) {
            return try decoder.decode([CommandWrapper].self, from: data)
        }

        return []
    }

    /// Clear all pending commands (called by daemon after processing)
    public func clearPendingCommands() throws {
        // Remove file
        try? fileManager.removeItem(atPath: Self.commandsFile)

        // Also clear UserDefaults
        defaults?.removeObject(forKey: Keys.commands)
        defaults?.synchronize()
    }

    /// Mark a specific command as processed by removing it
    public func markCommandProcessed(_ commandId: UUID) throws {
        var commands = try loadPendingCommands()
        commands.removeAll { $0.id == commandId }

        if commands.isEmpty {
            try? fileManager.removeItem(atPath: Self.commandsFile)
            defaults?.removeObject(forKey: Keys.commands)
        } else {
            let data = try encoder.encode(commands)
            let url = URL(fileURLWithPath: Self.commandsFile)
            try data.write(to: url, options: .atomic)
            // 0o660 permissions
            try? fileManager.setAttributes([.posixPermissions: 0o660], ofItemAtPath: Self.commandsFile)
            if role == .daemon {
                try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.commandsFile)
            }
            defaults?.set(data, forKey: Keys.commands)
        }
        defaults?.synchronize()
    }

    // MARK: - Daemon Heartbeat

    /// Update daemon heartbeat (called periodically by daemon)
    public func updateDaemonHeartbeat() {
        let timestamp = Date().timeIntervalSince1970

        // Primary: write to file
        ensureIPCDirectory()
        let timestampString = String(timestamp)
        try? timestampString.write(toFile: Self.heartbeatFile, atomically: true, encoding: .utf8)
        // 0o640: owner (root) rw-, group (admin) r--, others ---
        // Daemon writes, app (in admin group) reads
        try? fileManager.setAttributes([.posixPermissions: 0o640], ofItemAtPath: Self.heartbeatFile)
        if role == .daemon {
            try? fileManager.setAttributes([.groupOwnerAccountID: Self.adminGroupID], ofItemAtPath: Self.heartbeatFile)
        }

        // Also update UserDefaults if available
        defaults?.set(timestamp, forKey: Keys.daemonHeartbeat)
        defaults?.synchronize()
    }

    /// Check if daemon is alive (heartbeat within threshold)
    public func isDaemonAlive(threshold: TimeInterval = 15.0) -> Bool {
        // Primary: check file-based heartbeat
        if fileManager.fileExists(atPath: Self.heartbeatFile),
           let contents = try? String(contentsOfFile: Self.heartbeatFile, encoding: .utf8),
           let timestamp = TimeInterval(contents) {
            return Date().timeIntervalSince1970 - timestamp < threshold
        }

        // Fallback: check UserDefaults
        if let defaults,
           let timestamp = defaults.object(forKey: Keys.daemonHeartbeat) as? TimeInterval {
            return Date().timeIntervalSince1970 - timestamp < threshold
        }

        return false
    }

    /// Get last daemon heartbeat time
    public func lastDaemonHeartbeat() -> Date? {
        // Primary: check file-based heartbeat
        if fileManager.fileExists(atPath: Self.heartbeatFile),
           let contents = try? String(contentsOfFile: Self.heartbeatFile, encoding: .utf8),
           let timestamp = TimeInterval(contents) {
            return Date(timeIntervalSince1970: timestamp)
        }

        // Fallback: check UserDefaults
        if let defaults,
           let timestamp = defaults.object(forKey: Keys.daemonHeartbeat) as? TimeInterval {
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

    /// Clear all IPC data (for testing/debugging only)
    public func clearAllData() {
        guard let defaults else { return }
        defaults.removeObject(forKey: Keys.state)
        defaults.removeObject(forKey: Keys.commands)
        defaults.removeObject(forKey: Keys.daemonHeartbeat)
        defaults.synchronize()
    }

    /// Get debug description of current IPC state
    public func debugDescription() -> String {
        var lines: [String] = []
        lines.append("=== IPCManager Debug Info ===")
        lines.append("App Group: \(Self.appGroupIdentifier)")
        lines.append("Available: \(isAvailable)")

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
        case appGroupsUnavailable
        case encodingFailed(underlying: Error)
        case decodingFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .appGroupsUnavailable:
                return "App Groups not available. Check entitlements configuration."
            case .encodingFailed(let e):
                return "Failed to encode data: \(e.localizedDescription)"
            case .decodingFailed(let e):
                return "Failed to decode data: \(e.localizedDescription)"
            }
        }
    }
}
