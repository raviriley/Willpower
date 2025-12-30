//
//  IPCManager.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation

/// Manages IPC between Willpower app and daemon via App Groups
/// Thread-safe due to UserDefaults' internal synchronization
public final class IPCManager: @unchecked Sendable {

    // MARK: - Constants

    /// App Group identifier - must match in both app and daemon entitlements
    /// Format: group.TEAMID.com.yourcompany.willpower
    public static let appGroupIdentifier = "group.P5AM8FWTFW.raviriley.Willpower"

    /// Keys for UserDefaults storage
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

    /// Whether App Groups access is available
    public var isAvailable: Bool {
        return defaults != nil
    }

    // MARK: - Initialization

    public init() {
        self.defaults = UserDefaults(suiteName: Self.appGroupIdentifier)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        // Use ISO8601 date encoding for consistency
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if defaults == nil {
            print("[IPCManager] WARNING: Could not access App Group UserDefaults.")
            print("[IPCManager] Ensure '\(Self.appGroupIdentifier)' is in entitlements.")
        }
    }

    // MARK: - State Management

    /// Save the current Willpower state (typically called by daemon)
    public func saveState(_ state: WillpowerState) throws {
        guard let defaults else {
            throw IPCError.appGroupsUnavailable
        }

        let data = try encoder.encode(state)
        defaults.set(data, forKey: Keys.state)
        defaults.synchronize()
    }

    /// Load the current Willpower state
    public func loadState() throws -> WillpowerState? {
        guard let defaults else {
            throw IPCError.appGroupsUnavailable
        }

        guard let data = defaults.data(forKey: Keys.state) else {
            return nil
        }

        return try decoder.decode(WillpowerState.self, from: data)
    }

    /// Load state or return a default empty state
    public func loadStateOrDefault() -> WillpowerState {
        do {
            return try loadState() ?? WillpowerState()
        } catch {
            print("[IPCManager] Error loading state: \(error). Returning default.")
            return WillpowerState()
        }
    }

    // MARK: - Commands (App -> Daemon)

    /// Queue a command for the daemon to process
    public func queueCommand(_ command: DaemonCommand) throws {
        guard let defaults else {
            throw IPCError.appGroupsUnavailable
        }

        // Load existing commands
        var commands = (try? loadPendingCommands()) ?? []

        // Add new command with wrapper
        let wrapper = CommandWrapper(command: command)
        commands.append(wrapper)

        // Save back
        let data = try encoder.encode(commands)
        defaults.set(data, forKey: Keys.commands)
        defaults.synchronize()
    }

    /// Load pending commands (called by daemon)
    public func loadPendingCommands() throws -> [CommandWrapper] {
        guard let defaults else {
            throw IPCError.appGroupsUnavailable
        }

        guard let data = defaults.data(forKey: Keys.commands) else {
            return []
        }

        return try decoder.decode([CommandWrapper].self, from: data)
    }

    /// Clear all pending commands (called by daemon after processing)
    public func clearPendingCommands() throws {
        guard let defaults else {
            throw IPCError.appGroupsUnavailable
        }

        defaults.removeObject(forKey: Keys.commands)
        defaults.synchronize()
    }

    /// Mark a specific command as processed by removing it
    public func markCommandProcessed(_ commandId: UUID) throws {
        guard let defaults else {
            throw IPCError.appGroupsUnavailable
        }

        var commands = try loadPendingCommands()
        commands.removeAll { $0.id == commandId }

        if commands.isEmpty {
            defaults.removeObject(forKey: Keys.commands)
        } else {
            let data = try encoder.encode(commands)
            defaults.set(data, forKey: Keys.commands)
        }
        defaults.synchronize()
    }

    // MARK: - Daemon Heartbeat

    /// Update daemon heartbeat (called periodically by daemon)
    public func updateDaemonHeartbeat() {
        guard let defaults else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.daemonHeartbeat)
        defaults.synchronize()
    }

    /// Check if daemon is alive (heartbeat within threshold)
    public func isDaemonAlive(threshold: TimeInterval = 15.0) -> Bool {
        guard let defaults,
              let timestamp = defaults.object(forKey: Keys.daemonHeartbeat) as? TimeInterval else {
            return false
        }
        return Date().timeIntervalSince1970 - timestamp < threshold
    }

    /// Get last daemon heartbeat time
    public func lastDaemonHeartbeat() -> Date? {
        guard let defaults,
              let timestamp = defaults.object(forKey: Keys.daemonHeartbeat) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
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

    /// Reset visit counts for patterns
    public func resetVisitCounts(patternIds: [UUID]? = nil) throws {
        try queueCommand(.resetVisitCounts(patternIds: patternIds))
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
