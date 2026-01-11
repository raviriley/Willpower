# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Willpower is a macOS website blocker app built with SwiftUI. It blocks websites via `/etc/hosts` manipulation using a privileged daemon architecture.

**Structure:**
- **Willpower/** - Main SwiftUI app (sandboxed, manages UI/configuration)
- **WillpowerDaemon/** - Privileged CLI daemon (hardened runtime, enforces blocking)
- **WillpowerKit/** - Shared Swift Package (models, hosts manipulation, monitoring)

## Build Commands

```bash
# Build in Xcode
# Select scheme (Willpower or WillpowerDaemon) then Cmd+B

# Build WillpowerKit package
cd WillpowerKit && swift build

# Run tests (when implemented)
cd WillpowerKit && swift test
```

## Architecture

### Privilege Separation Model
- **App** (sandboxed): User-facing SwiftUI interface
- **Daemon** (privileged): Runs as LaunchDaemon, has write access to `/etc/hosts`
- **Shared Kit**: Common models and logic, no external dependencies

### Key Technologies
- SwiftUI for UI
- SMAppService.daemon for privileged helper registration (macOS 13+)
- File-based IPC at `/Library/Application Support/Willpower/ipc/`
- PF (packet filter) firewall for network-level blocking
- AppleScript for browser URL monitoring

### Data Flow
1. User creates blocklists in SwiftUI app (synced via IPC to daemon)
2. App communicates configuration to daemon via file-based IPC (state.json, commands.json)
3. Daemon modifies `/etc/hosts` with blocked domains
4. Daemon also applies PF firewall rules for network-level blocking
5. Domains are blocked using markers: `## WILLPOWER-START` / `## WILLPOWER-END`

### IPC Architecture
- **Location**: `/Library/Application Support/Willpower/ipc/`
- **Files**: `state.json` (daemon → app), `commands.json` (app → daemon), `heartbeat`
- **Permissions**: Role-based (root:admin group, 0o640/0o660)
- **Note**: App Groups don't work due to macOS macl blocking root access. XPC planned for future.

### Concurrency Model
- Swift Concurrency with MainActor default isolation
- Async/await for privileged operations

## Implementation Status

Core functionality is complete. See `CHANGELOG.md` for detailed status:
- **Phase 1 (NOW)**: Core features & polish - mostly complete
- **Phase 2 (LATER)**: Distribution & infrastructure - in progress
- **Phase 3 (POST-LAUNCH)**: Feature enhancements - planned

Key completed features:
- Full SwiftUI app with MVVM architecture
- Daemon with SMAppService.daemon registration
- Dual-layer blocking (hosts file + PF firewall)
- Schedule-based and visit-count triggers
- Browser URL monitoring via AppleScript

## Key Files

- `WillpowerKit/Sources/WillpowerKit/Models.swift` - BlocklistConfig, TriggerConfig, WillpowerState structs
- `WillpowerKit/Sources/WillpowerKit/IPCManager.swift` - File-based IPC between app and daemon
- `WillpowerKit/Sources/WillpowerKit/HostsManager.swift` - /etc/hosts manipulation
- `WillpowerKit/Sources/WillpowerKit/PacketFilterManager.swift` - PF firewall rules
- `WillpowerKit/Sources/WillpowerKit/Logger.swift` - Unified os_log logging
- `WillpowerKit/Sources/WillpowerKit/BrowserMonitor.swift` - AppleScript-based browser URL monitoring
- `WillpowerKit/Sources/WillpowerKit/TriggerEvaluator.swift` - Schedule and visit-count trigger evaluation
- `WillpowerDaemon/main.swift` - Daemon entry point and run loop
- `Willpower/ViewModels/WillpowerViewModel.swift` - Central app state management
- `Willpower/DaemonManager.swift` - SMAppService.daemon registration
- `CHANGELOG.md` - Development TODOs
- `XPC_TODO.md` - Planned XPC migration (future release)

## Build Configuration

- **Deployment Target**: macOS 14.0
- **Swift**: 6.2 (tools version), compiled with Swift 6.2.3
- **Architecture**: arm64
- App Sandbox enabled for main app
- Hardened Runtime enabled for both app and daemon

## Releases

Always use `scripts/github-release.sh <version>` for releases. This script:
1. Builds, signs, notarizes, and creates DMG
2. Commits version bump to project.pbxproj
3. Generates appcast.xml for Sparkle updates
4. Creates GitHub Release with DMG and appcast
5. Syncs release tag locally
