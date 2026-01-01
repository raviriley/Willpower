this is a rough draft of an implementation plan for Willpower, specifically tailored to your **Xcode-based monorepo** structure (`Willpower` app, `WillpowerDaemon` executable, and `WillpowerKit` package).

treat this as a rough draft and a starting point for the project, and not as a final plan. especially for the code, treat it is pseudo code and not as a final implementation.

# Willpower (SelfControl 2.0) - Implementation Plan

## Project Goals

**Primary**: Replace SelfControl with a Swift-native, SwiftUI app that blocks websites via `/etc/hosts` using modern macOS APIs.

**Features**:
- Multiple configurable blocklists with triggers (time-based, visit-count)
- Traffic monitoring via `Network.framework` (no proxy overhead)
- LaunchDaemon for unbreakable enforcement
- SwiftUI interface with SwiftData persistence
- App Sandbox + `SMJobBless` for privileged operations

## Architectural Structure

```
.
└── Willpower/                  <-- Top folder
    ├── Willpower/              <-- App Source (SwiftUI + SwiftData)
    ├── WillpowerDaemon/        <-- Background Engine (Privileged CLI)
    ├── WillpowerKit/           <-- Shared Logic (Hosts, Models, Monitoring)
    └── Willpower.xcodeproj
```

## Phase 1: Core Engine

### 1.1 Shared Logic (`WillpowerKit`)

**Action**: Implement the data models and hosts manager in the shared package so both the App and Daemon can use them.

**File**: `WillpowerKit/Sources/WillpowerKit/Models.swift`
```swift
import Foundation
import SwiftData

// Note: SwiftData models must be available to the App, but simpler structs are better for the shared package
// to avoid complex dependencies in the Daemon if SwiftData isn't strictly needed there yet.
// For now, we define the core configuration structure.

public struct BlocklistConfig: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var domains: [String]
    public var triggers: [TriggerConfig]
    public var isActive: Bool
    
    public init(id: UUID = UUID(), name: String, domains: [String], triggers: [TriggerConfig], isActive: Bool = false) {
        self.id = id
        self.name = name
        self.domains = domains
        self.triggers = triggers
        self.isActive = isActive
    }
}

public struct TriggerConfig: Codable {
    public enum TriggerType: String, Codable {
        case time
        case visit
    }
    public var type: TriggerType
    public var details: [String: String] // Simple key-value store for config
    
    public init(type: TriggerType, details: [String : String]) {
        self.type = type
        self.details = details
    }
}
```

**File**: `WillpowerKit/Sources/WillpowerKit/HostsManager.swift`
```swift
import Foundation

@MainActor
public class HostsManager {
    private let hostsURL = URL(fileURLWithPath: "/etc/hosts")
    
    public init() {}
    
    public func applyBlocklist(_ domains: [String]) async throws {
        // Prepare the entries
        let entries = domains.map { "127.0.0.1 \($0)" }
        let markerStart = "## WILLPOWER-START"
        let markerEnd = "## WILLPOWER-END"
        let blockBlock = "\(markerStart)\n" + entries.joined(separator: "\n") + "\n\(markerEnd)"
        
        // Read current hosts
        // NOTE: In the real daemon, we read/write directly. In the App, we might need a helper.
        // For Phase 1 testing (sandbox disabled on Daemon), we just try to write.
        
        // Write logic (simplified for phase 1)
        let currentHosts = try String(contentsOf: hostsURL)
        if currentHosts.contains(markerStart) {
             // Logic to replace existing block would go here
        } else {
             let newHosts = currentHosts + "\n" + blockBlock
             let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("hosts_temp")
             try newHosts.write(to: tempURL, atomically: true, encoding: .utf8)
             try await privilegedCopy(tempURL, to: hostsURL)
        }
    }
    
    private func privilegedCopy(_ source: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["cp", source.path, destination.path]
        
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "HostsError", code: Int(process.terminationStatus), userInfo: nil))
                }
            }
            try? process.run()
        }
    }
}
```

### 1.2 Verify Build
1.  Select `Willpower` scheme -> Build (Cmd+B).
2.  Select `WillpowerDaemon` scheme -> Build (Cmd+B).
3.  Ensure no linking errors occur.

## Phase 2: Traffic Monitoring

### 2.1 Network Monitor (`WillpowerKit`)

**Action**: Create a monitor that can sniff traffic patterns using `Network.framework`.

**File**: `WillpowerKit/Sources/WillpowerKit/NetworkMonitor.swift`
```swift
import Network
import Foundation

public class NetworkMonitor {
    private var monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.willpower.network")
    
    public init() {
        self.monitor = NWPathMonitor()
    }
    
    public func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            // This is high-level interface monitoring
            // Actual packet inspection (detecting "shorts") usually requires 
            // a Content Filter Provider (Network Extension) or analyzing
            // global state if not using a proxy.
            
            // For Phase 1 "Shorts" detection without a proxy:
            // We can't see full URLs (like /shorts) via NWPathMonitor or standard sockets 
            // because of HTTPS. 
            
            // ARCHITECTURE ADJUSTMENT:
            // To detect "youtube.com/shorts" specifically without a proxy, we must use
            // a Safari Web Extension helper OR accept that we block "youtube.com" entirely.
            // OR use the 'lsof' / 'tcpdump' polling method from the original plan.
        }
        monitor.start(queue: queue)
    }
    
    // Polling fallback (Simple & effective for "Shorts" detection via browser history or window title)
    // A more robust method involves using AppleScript/Accessibility to check active tab URL.
    public func checkActiveTabForShorts() async -> Bool {
        // Implementation using NSAppleScript to query Safari/Chrome active tab
        return false 
    }
}
```

### 2.2 Daemon Implementation (`WillpowerDaemon`)

**Action**: Wire up the daemon to run the logic.

**File**: `WillpowerDaemon/main.swift`
```swift
import Foundation
import WillpowerKit

@main
struct WillpowerDaemon {
    static func main() async {
        print("Willpower Daemon Starting...")
        let manager = HostsManager()
        
        // Simple run loop for now
        while true {
            // Logic to check triggers
            // e.g. check time, check active tabs
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000) // Sleep 5s
        }
    }
}
```

## Phase 3: SwiftUI App

### 3.1 UI & Persistence (`Willpower`)

**Action**: Build the UI to manage blocklists.

**File**: `Willpower/WillpowerApp.swift`
```swift
import SwiftUI
import SwiftData

@main
struct WillpowerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Blocklist.self) // Define Blocklist SwiftData model in App target
    }
}
```

**Note**: You will define the `Blocklist` SwiftData model inside the `Willpower` app target (not Kit) because SwiftData is easiest to manage within the main app bundle for now, mapping it to `BlocklistConfig` structs when passing data to the Daemon.

## Phase 4: LaunchDaemon Integration

### 4.1 Installer Logic

**Action**: The App needs to "install" the Daemon.

1.  **Build Daemon**: Archive the `WillpowerDaemon` target.
2.  **Embed**: Copy the compiled binary into the `Willpower.app` bundle (Build Phases > Copy Files).
3.  **Install**:
    *   On first run, `Willpower.app` checks if `/Library/LaunchDaemons/com.yourname.willpower.plist` exists.
    *   If not, it prompts for Admin password (via `SMJobBless` or a simple `NSAppleScript` wrapper for phase 1) to copy the binary to `/usr/local/bin` and the plist to `/Library/LaunchDaemons`.

## Phase 5: Testing

### 5.1 Manual Test Plan
1.  **Run App**: Create a blocklist for `youtube.com`.
2.  **Trigger**: Click "Activate".
3.  **Verify**: Open Terminal, `cat /etc/hosts`. Ensure `127.0.0.1 youtube.com` is present.
4.  **Verify**: Open Safari, try `youtube.com`. It should fail.
5.  **Reboot**: Restart Mac. Verify block persists.
