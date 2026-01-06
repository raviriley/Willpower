# XPC IPC Redesign - Complete Implementation Plan

## Executive Summary

Replace file-based IPC (`/Library/Application Support/Willpower/ipc/`) with XPC Mach service communication. The daemon will expose an XPC listener that the app connects to directly, eliminating filesystem race conditions, permission issues, and polling delays.

**Why XPC?**
- App Groups macl blocks root daemon access (confirmed experimentally)
- File-based IPC has race conditions, polling latency, and 0o777 security concerns
- XPC is Apple's recommended pattern for app ↔ privileged helper communication
- Real-time bidirectional communication (no more 5-second polling)
- Built-in security via audit token verification

---

## Architecture Overview

```
┌─────────────────┐         XPC Mach Service         ┌─────────────────────┐
│   Willpower     │ ◄──────────────────────────────► │  WillpowerDaemon    │
│   (User App)    │    raviriley.WillpowerDaemon     │  (Root Daemon)      │
│                 │                                   │                     │
│  NSXPCConnection│                                   │  NSXPCListener      │
│  (client)       │                                   │  (server)           │
└─────────────────┘                                   └─────────────────────┘
        │                                                      │
        │ Calls: executeCommand(), getState()                  │ Modifies:
        │ Receives: state updates, confirmations               │ /etc/hosts
        │                                                      │ pf firewall
        ▼                                                      ▼
   SwiftUI Views                                         HostsManager
   WillpowerViewModel                                    PacketFilterManager
```

---

## Phase 1: XPC Protocol Definition

### 1.1 Create XPC Protocol File

**New File:** `WillpowerKit/Sources/WillpowerKit/WillpowerXPCProtocol.swift`

```swift
import Foundation

/// XPC Protocol for App → Daemon communication
/// Note: @objc required for XPC, all types must be Objective-C compatible
@objc public protocol WillpowerDaemonProtocol {

    // MARK: - Commands (App → Daemon)

    /// Execute a daemon command (JSON-encoded DaemonCommand)
    /// - Parameters:
    ///   - commandJSON: JSON string of CommandWrapper
    ///   - reply: Callback with success bool and optional error message
    func executeCommand(_ commandJSON: String, reply: @escaping (Bool, String?) -> Void)

    /// Request current state from daemon
    /// - Parameter reply: Callback with JSON-encoded WillpowerState or nil on error
    func getState(reply: @escaping (String?) -> Void)

    /// Check if daemon is alive (simple ping)
    /// - Parameter reply: Returns daemon version string
    func ping(reply: @escaping (String) -> Void)
}

/// XPC Protocol for Daemon → App callbacks (optional, for real-time updates)
@objc public protocol WillpowerAppProtocol {

    /// Daemon notifies app of state change
    /// - Parameter stateJSON: JSON-encoded WillpowerState
    func stateDidChange(_ stateJSON: String)

    /// Daemon notifies app of block activation/deactivation
    /// - Parameters:
    ///   - blocklistId: UUID string of affected blocklist
    ///   - isActive: Whether blocklist is now active
    func blockStatusChanged(_ blocklistId: String, isActive: Bool)
}
```

### 1.2 XPC Service Name Constant

```swift
/// Mach service name for XPC communication
/// Must match MachServices key in daemon plist
public let WillpowerXPCServiceName = "raviriley.WillpowerDaemon.xpc"
```

---

## Phase 2: Daemon XPC Listener

### 2.1 Update Daemon Plist

**File:** `WillpowerDaemon/raviriley.WillpowerDaemon.plist`

Add MachServices key:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>raviriley.WillpowerDaemon</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/WillpowerDaemon</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>UserName</key>
    <string>root</string>

    <!-- NEW: XPC Mach Service -->
    <key>MachServices</key>
    <dict>
        <key>raviriley.WillpowerDaemon.xpc</key>
        <true/>
    </dict>

    <key>StandardErrorPath</key>
    <string>/var/log/willpower-daemon.err.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/willpower-daemon.out.log</string>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>raviriley.Willpower</string>
    </array>
</dict>
</plist>
```

### 2.2 Create XPC Service Handler

**New File:** `WillpowerDaemon/XPCService.swift`

```swift
import Foundation
import WillpowerKit

/// Handles incoming XPC connections and implements the daemon protocol
class WillpowerXPCService: NSObject, WillpowerDaemonProtocol {

    private let stateManager: DaemonStateManager  // Reference to daemon state
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(stateManager: DaemonStateManager) {
        self.stateManager = stateManager
        super.init()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - WillpowerDaemonProtocol

    func executeCommand(_ commandJSON: String, reply: @escaping (Bool, String?) -> Void) {
        guard let data = commandJSON.data(using: .utf8) else {
            reply(false, "Invalid JSON encoding")
            return
        }

        do {
            let wrapper = try decoder.decode(CommandWrapper.self, from: data)

            // Process command immediately (no queue needed with XPC)
            let result = stateManager.processCommand(wrapper.command)

            switch result {
            case .success:
                reply(true, nil)
            case .rejected(let reason):
                reply(false, reason)
            case .error(let message):
                reply(false, message)
            }
        } catch {
            reply(false, "Failed to decode command: \(error.localizedDescription)")
        }
    }

    func getState(reply: @escaping (String?) -> Void) {
        do {
            let state = stateManager.currentState
            let data = try encoder.encode(state)
            reply(String(data: data, encoding: .utf8))
        } catch {
            reply(nil)
        }
    }

    func ping(reply: @escaping (String) -> Void) {
        reply(stateManager.daemonVersion)
    }
}
```

### 2.3 Create XPC Listener Delegate

**New File:** `WillpowerDaemon/XPCListenerDelegate.swift`

```swift
import Foundation
import WillpowerKit

/// Delegate that handles incoming XPC connections
class XPCListenerDelegate: NSObject, NSXPCListenerDelegate {

    private let stateManager: DaemonStateManager
    private var activeConnections: [NSXPCConnection] = []

    init(stateManager: DaemonStateManager) {
        self.stateManager = stateManager
        super.init()
    }

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {

        // Security: Verify caller is our app via audit token
        // TODO: Add audit token verification for production
        // let auditToken = connection.auditToken
        // Verify: auditToken matches raviriley.Willpower signing identity

        // Configure the connection
        connection.exportedInterface = NSXPCInterface(with: WillpowerDaemonProtocol.self)
        connection.exportedObject = WillpowerXPCService(stateManager: stateManager)

        // Optional: Set up reverse connection for daemon → app callbacks
        connection.remoteObjectInterface = NSXPCInterface(with: WillpowerAppProtocol.self)

        // Handle connection lifecycle
        connection.interruptionHandler = { [weak self] in
            self?.handleConnectionInterrupted(connection)
        }
        connection.invalidationHandler = { [weak self] in
            self?.handleConnectionInvalidated(connection)
        }

        // Track active connections
        activeConnections.append(connection)
        connection.resume()

        log("[XPC] Accepted new connection (total: \(activeConnections.count))")
        return true
    }

    private func handleConnectionInterrupted(_ connection: NSXPCConnection) {
        log("[XPC] Connection interrupted")
    }

    private func handleConnectionInvalidated(_ connection: NSXPCConnection) {
        activeConnections.removeAll { $0 === connection }
        log("[XPC] Connection invalidated (remaining: \(activeConnections.count))")
    }

    /// Broadcast state change to all connected apps
    func broadcastStateChange(_ state: WillpowerState) {
        guard let stateJSON = try? JSONEncoder().encode(state),
              let jsonString = String(data: stateJSON, encoding: .utf8) else { return }

        for connection in activeConnections {
            let proxy = connection.remoteObjectProxy as? WillpowerAppProtocol
            proxy?.stateDidChange(jsonString)
        }
    }
}
```

### 2.4 Update Daemon main.swift

**File:** `WillpowerDaemon/main.swift`

Replace file-based IPC with XPC listener:

```swift
import Foundation
import WillpowerKit

private let daemonVersion = "2.0.0"  // Major version bump for XPC

// ... existing logging setup ...

// MARK: - XPC Setup

// Create state manager (encapsulates daemon state and business logic)
let stateManager = DaemonStateManager(version: daemonVersion)

// Create and configure XPC listener
let listenerDelegate = XPCListenerDelegate(stateManager: stateManager)
let listener = NSXPCListener(machServiceName: WillpowerXPCServiceName)
listener.delegate = listenerDelegate
listener.resume()

log("[WillpowerDaemon] XPC listener started on: \(WillpowerXPCServiceName)")

// MARK: - Main Run Loop

// Simplified run loop - no more file polling needed!
// Only handles: trigger evaluation, block cleanup, hosts/pf enforcement

Task {
    while true {
        // Evaluate time-based and schedule-based triggers
        stateManager.evaluateTriggers()

        // Clean up expired blocks
        stateManager.cleanupExpiredBlocks()

        // Apply blocking rules (hosts + pf)
        stateManager.applyBlocks()

        // Sleep until next evaluation
        try? await Task.sleep(nanoseconds: UInt64(5.0 * 1_000_000_000))
    }
}

// Keep daemon alive
dispatchMain()
```

---

## Phase 3: Refactor Daemon State Management

### 3.1 Create DaemonStateManager

**New File:** `WillpowerDaemon/DaemonStateManager.swift`

Extract state management from main.swift into a proper class:

```swift
import Foundation
import WillpowerKit

/// Result of processing a command
enum CommandResult {
    case success
    case rejected(reason: String)
    case error(message: String)
}

/// Manages daemon state and business logic
/// Thread-safe for XPC concurrent access
class DaemonStateManager {

    let daemonVersion: String

    private let hostsManager = HostsManager()
    private let packetFilterManager = PacketFilterManager()
    private let triggerEvaluator = TriggerEvaluator()

    private let stateQueue = DispatchQueue(label: "com.willpower.daemon.state")
    private var _state: WillpowerState
    private var previousBlockedDomains: Set<String>? = nil

    var currentState: WillpowerState {
        stateQueue.sync { _state }
    }

    init(version: String) {
        self.daemonVersion = version
        self._state = WillpowerState()
        self._state.daemonVersion = version
    }

    /// Process a command from the app (called via XPC)
    func processCommand(_ command: DaemonCommand) -> CommandResult {
        stateQueue.sync {
            // ... existing command processing logic from main.swift ...
            // Move switch statement here
        }
    }

    /// Evaluate triggers (called from run loop)
    func evaluateTriggers() {
        stateQueue.sync {
            // ... existing trigger evaluation logic ...
        }
    }

    /// Clean up expired blocks
    func cleanupExpiredBlocks() {
        stateQueue.sync {
            // ... existing cleanup logic ...
        }
    }

    /// Apply blocking rules
    func applyBlocks() {
        let domains = stateQueue.sync {
            collectBlockedDomains()
        }

        // Apply to hosts and pf (outside lock - I/O operations)
        applyHostsBlocking(domains)
        applyPFBlocking(domains)
    }
}
```

---

## Phase 4: App XPC Client

### 4.1 Create XPCClient

**New File:** `Willpower/Services/XPCClient.swift`

```swift
import Foundation
import WillpowerKit

/// XPC client for communicating with the daemon
@MainActor
class XPCClient: ObservableObject {

    @Published private(set) var isConnected = false
    @Published private(set) var daemonVersion: String?

    private var connection: NSXPCConnection?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Connect to daemon XPC service
    func connect() {
        guard connection == nil else { return }

        let conn = NSXPCConnection(machServiceName: WillpowerXPCServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: WillpowerDaemonProtocol.self)

        // Optional: Export app protocol for daemon callbacks
        conn.exportedInterface = NSXPCInterface(with: WillpowerAppProtocol.self)
        conn.exportedObject = self

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.handleInterruption()
            }
        }

        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.handleInvalidation()
            }
        }

        conn.resume()
        connection = conn

        // Verify connection with ping
        ping()
    }

    /// Disconnect from daemon
    func disconnect() {
        connection?.invalidate()
        connection = nil
        isConnected = false
        daemonVersion = nil
    }

    // MARK: - Commands

    /// Send a command to the daemon
    func sendCommand(_ command: DaemonCommand) async throws {
        guard let proxy = daemonProxy else {
            throw XPCError.notConnected
        }

        let wrapper = CommandWrapper(command: command)
        let data = try encoder.encode(wrapper)
        guard let json = String(data: data, encoding: .utf8) else {
            throw XPCError.encodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.executeCommand(json) { success, errorMessage in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: XPCError.commandRejected(errorMessage ?? "Unknown error"))
                }
            }
        }
    }

    /// Get current state from daemon
    func getState() async throws -> WillpowerState {
        guard let proxy = daemonProxy else {
            throw XPCError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.getState { stateJSON in
                guard let json = stateJSON,
                      let data = json.data(using: .utf8) else {
                    continuation.resume(throwing: XPCError.invalidResponse)
                    return
                }

                do {
                    let state = try self.decoder.decode(WillpowerState.self, from: data)
                    continuation.resume(returning: state)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Ping daemon to check connectivity
    func ping() {
        daemonProxy?.ping { [weak self] version in
            Task { @MainActor in
                self?.isConnected = true
                self?.daemonVersion = version
            }
        }
    }

    // MARK: - Private

    private var daemonProxy: WillpowerDaemonProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { error in
            print("[XPCClient] Remote object error: \(error)")
        } as? WillpowerDaemonProtocol
    }

    private func handleInterruption() {
        isConnected = false
        // Attempt reconnect after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            connect()
        }
    }

    private func handleInvalidation() {
        isConnected = false
        connection = nil
    }
}

// MARK: - WillpowerAppProtocol (Daemon → App callbacks)

extension XPCClient: WillpowerAppProtocol {

    nonisolated func stateDidChange(_ stateJSON: String) {
        // Handle real-time state updates from daemon
        guard let data = stateJSON.data(using: .utf8),
              let state = try? decoder.decode(WillpowerState.self, from: data) else { return }

        Task { @MainActor in
            // Notify view model of state change
            NotificationCenter.default.post(
                name: .daemonStateChanged,
                object: nil,
                userInfo: ["state": state]
            )
        }
    }

    nonisolated func blockStatusChanged(_ blocklistId: String, isActive: Bool) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .blockStatusChanged,
                object: nil,
                userInfo: ["blocklistId": blocklistId, "isActive": isActive]
            )
        }
    }
}

// MARK: - Errors

enum XPCError: LocalizedError {
    case notConnected
    case encodingFailed
    case invalidResponse
    case commandRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to daemon"
        case .encodingFailed: return "Failed to encode command"
        case .invalidResponse: return "Invalid response from daemon"
        case .commandRejected(let reason): return "Command rejected: \(reason)"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let daemonStateChanged = Notification.Name("daemonStateChanged")
    static let blockStatusChanged = Notification.Name("blockStatusChanged")
}
```

### 4.2 Update WillpowerViewModel

**File:** `Willpower/ViewModels/WillpowerViewModel.swift`

Replace IPCManager usage with XPCClient:

```swift
// Replace:
private let ipcManager = IPCManager()

// With:
@Published var xpcClient = XPCClient()

// Replace syncState() polling with XPC:
func syncState() async {
    guard xpcClient.isConnected else {
        xpcClient.connect()
        return
    }

    do {
        let state = try await xpcClient.getState()
        // Update local state from daemon
        self.activeBlocks = state.activeBlocks.filter { !$0.isExpired }
        self.visitRecords = state.visitRecords
    } catch {
        print("[ViewModel] Failed to get state: \(error)")
    }
}

// Replace command sending:
func activateBlocklist(_ blocklist: BlocklistConfig, ...) async {
    do {
        let trigger = TimeBasedTrigger(durationSeconds: durationSeconds)
        let command = DaemonCommand.activateBlocklist(
            blocklistId: blocklist.id,
            trigger: TriggerConfig(timeBased: trigger),
            isLocked: isLocked
        )
        try await xpcClient.sendCommand(command)
    } catch {
        // Handle error
    }
}
```

---

## Phase 5: Remove File-Based IPC

### 5.1 Files to Delete

- Keep IPCManager.swift but mark all filesystem methods as deprecated
- Or remove entirely if not needed for any fallback

### 5.2 Files to Modify

| File | Changes |
|------|---------|
| `WillpowerKit/Sources/WillpowerKit/IPCManager.swift` | Delete or deprecate file-based methods |
| `WillpowerDaemon/main.swift` | Complete rewrite for XPC |
| `Willpower/ViewModels/WillpowerViewModel.swift` | Replace IPCManager with XPCClient |
| `Willpower/WillpowerApp.swift` | Initialize XPCClient, remove polling timer |
| `WillpowerDaemon/raviriley.WillpowerDaemon.plist` | Add MachServices key |

### 5.3 Files to Create

| File | Purpose |
|------|---------|
| `WillpowerKit/Sources/WillpowerKit/WillpowerXPCProtocol.swift` | XPC protocol definitions |
| `WillpowerDaemon/XPCService.swift` | XPC service implementation |
| `WillpowerDaemon/XPCListenerDelegate.swift` | Connection handling |
| `WillpowerDaemon/DaemonStateManager.swift` | Extracted state management |
| `Willpower/Services/XPCClient.swift` | App-side XPC client |

---

## Phase 6: Migration & Testing

### 6.1 Migration Steps

1. **Keep file-based IPC temporarily** as fallback during development
2. **Implement XPC alongside existing IPC** - both paths work
3. **Add feature flag** to switch between IPC modes
4. **Test XPC thoroughly** before removing file-based
5. **Remove file-based IPC** once XPC is stable

### 6.2 Testing Checklist

- [ ] Daemon starts and XPC listener registers
- [ ] App connects to XPC service
- [ ] Ping returns daemon version
- [ ] executeCommand works for all command types:
  - [ ] activateBlocklist
  - [ ] deactivateBlocklist
  - [ ] updateBlocklists
  - [ ] updateIndependentTriggers
  - [ ] deleteIndependentTrigger
  - [ ] forceSync
  - [ ] reportVisit
- [ ] getState returns valid WillpowerState
- [ ] Daemon → App callbacks work (stateDidChange)
- [ ] Connection survives daemon restart
- [ ] App reconnects after interruption
- [ ] Blocking works end-to-end (hosts + pf)
- [ ] Locked blocks cannot be deactivated
- [ ] Schedule triggers activate/deactivate
- [ ] Visit count triggers work

### 6.3 Daemon Restart Procedure

Same as before - must fully unregister:

```bash
sudo launchctl bootout system/raviriley.WillpowerDaemon
open /path/to/Willpower.app
tail -f /var/log/willpower-daemon.out.log
```

---

## Security Considerations

### Audit Token Verification

For production, add caller verification:

```swift
func listener(_ listener: NSXPCListener,
              shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {

    // Get audit token
    var token = audit_token_t()
    // ... extract from connection ...

    // Verify signing identity matches app
    let requirement = "identifier \"raviriley.Willpower\" and anchor apple generic"
    // Use SecCodeCheckValidity with requirement

    return isValid
}
```

### Entitlements

No additional entitlements needed - MachServices in plist is sufficient.

---

## Version Bump

- Daemon version: `1.0.1` → `2.0.0` (breaking IPC change)
- App should check daemon version and prompt user to reinstall if < 2.0.0

---

## Estimated Implementation Order

1. **XPC Protocol** (WillpowerXPCProtocol.swift) - 30 min
2. **Plist Update** (MachServices key) - 5 min
3. **DaemonStateManager** (extract from main.swift) - 2 hours
4. **XPCService + ListenerDelegate** - 1 hour
5. **Daemon main.swift rewrite** - 1 hour
6. **XPCClient** (app side) - 1 hour
7. **ViewModel updates** - 2 hours
8. **Testing & debugging** - 3+ hours
9. **Remove file-based IPC** - 30 min

**Total estimate: 1-2 days**

---

## Rollback Plan

If XPC doesn't work:
1. Keep `/Library/Application Support/Willpower/ipc/` as fallback
2. File-based IPC is functional (just has 0o777 permission concern)
3. Can revisit App Groups if macOS behavior changes

---

## References

- [Apple: Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- [Apple: Daemons and Services Programming Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/)
- [SMAppService Documentation](https://developer.apple.com/documentation/servicemanagement/smappservice)
