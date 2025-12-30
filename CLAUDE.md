# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Willpower is a macOS website blocker app ("SelfControl 2.0") built with SwiftUI. It blocks websites via `/etc/hosts` manipulation using a privileged daemon architecture.

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
- **App** (sandboxed): User-facing SwiftUI interface with SwiftData persistence
- **Daemon** (privileged): Runs as LaunchDaemon, has write access to `/etc/hosts`
- **Shared Kit**: Common models and logic, no external dependencies

### Key Technologies
- SwiftUI + SwiftData for UI and persistence
- Network.framework for traffic monitoring (planned)
- SMJobBless for privileged helper installation (planned)
- App Groups for IPC between app and daemon

### Data Flow
1. User creates blocklists in SwiftUI app (stored via SwiftData)
2. App communicates configuration to daemon (via App Groups)
3. Daemon modifies `/etc/hosts` with blocked domains
4. Domains are blocked using markers: `## WILLPOWER-START` / `## WILLPOWER-END`

### Concurrency Model
- Swift Concurrency with MainActor default isolation
- Async/await for privileged operations

## Implementation Status

Currently early-stage with boilerplate code. See `plan.md` for the 5-phase implementation roadmap:
- Phase 1: Core Engine (Models, HostsManager) - **in progress**
- Phase 2: Traffic Monitoring (Network.framework)
- Phase 3: SwiftUI App & Persistence
- Phase 4: LaunchDaemon Integration (SMJobBless)
- Phase 5: Manual Testing

## Key Files

- `WillpowerKit/Sources/WillpowerKit/Models.swift` - BlocklistConfig, TriggerConfig structs
- `WillpowerKit/Sources/WillpowerKit/HostsManager.swift` - /etc/hosts manipulation
- `WillpowerDaemon/main.swift` - Daemon entry point and run loop
- `Willpower/WillpowerApp.swift` - App entry with SwiftData ModelContainer
- `plan.md` - Detailed implementation plan with pseudo-code examples

## Build Configuration

- **Deployment Target**: macOS 15.6
- **Swift**: 6.2 (tools version), compiled with Swift 6.2.3
- **Architecture**: arm64
- App Sandbox enabled for main app
- Hardened Runtime enabled for both app and daemon
