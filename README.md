# Willpower

A macOS website blocker that uses `/etc/hosts` manipulation via a privileged daemon. Modern Swift replacement for SelfControl.

## Features

- Block websites via /etc/hosts manipulation
- PF (packet filter) firewall for network-level blocking
- Browser URL monitoring for visit-count triggers (supports Safari, Chrome, Firefox, Arc, Brave, Edge)
- Schedule-based and manual activation
- Unbreakable blocking with daemon enforcement ("willpower")
- Blocklist presets for common categories (social media, news, streaming, gaming)

## Requirements

- macOS 15.6+
- Apple Silicon (arm64)
- Xcode 16+ (for building)

## Installation

### Build from Source

1. Clone the repository
2. Open `Willpower.xcodeproj` in Xcode
3. Select the `Willpower` scheme
4. Build and Run (Cmd+R)

### First Launch

1. Complete the onboarding flow
2. Approve daemon in **System Settings > General > Login Items**
3. Grant Automation permission when prompted (for browser URL monitoring)

## Architecture

```
Willpower/
├── WillpowerApp.swift          # App entry point
├── ContentView.swift           # Main navigation structure
├── DaemonManager.swift         # LaunchDaemon registration
├── ViewModels/
│   └── WillpowerViewModel.swift  # Central state & IPC
└── Views/
    ├── SidebarView.swift
    ├── Status/                 # Dashboard views
    ├── Blocklists/             # CRUD + activation
    ├── Schedules/              # Time-based automation
    ├── Triggers/               # Visit-count automation
    └── Components/             # Reusable UI

WillpowerDaemon/
├── main.swift                  # Run loop & command processing
└── raviriley.WillpowerDaemon.plist

WillpowerKit/
└── Sources/WillpowerKit/
    ├── Models.swift            # BlocklistConfig, TriggerConfig, etc.
    ├── IPCManager.swift        # File-based IPC
    ├── HostsManager.swift      # /etc/hosts manipulation
    ├── PacketFilterManager.swift # PF firewall rules
    ├── BrowserMonitor.swift    # URL polling
    └── TriggerEvaluator.swift  # Schedule/visit evaluation
```

### Privilege Separation

- **Willpower/** - Sandboxed SwiftUI app (UI/configuration)
- **WillpowerDaemon/** - Root daemon (enforces blocking via SMAppService.daemon)
- **WillpowerKit/** - Shared Swift package (models, blocking logic)

### IPC Flow

```
[App] → /Library/Application Support/Willpower/ipc/commands.json → [Daemon]
[Daemon] → /Library/Application Support/Willpower/ipc/state.json → [App]
[Daemon] → /Library/Application Support/Willpower/ipc/heartbeat → [App] (liveness check)
```

### Key Behaviors

#### Locked Blocks
When a blocklist is activated with `isLocked: true`, it cannot be deactivated until expiration. This is the "willpower" in Willpower - users can't bypass their own blocks.

#### Add-Only Domain Editing
Active blocklists can have domains added (immediately blocked), but existing domains cannot be removed until the block expires. Prevents circumventing blocks by deleting domains.

#### Schedule Activation
Daemon evaluates schedule triggers every 5 seconds. When the current time falls within a schedule window, the blocklist activates. Schedule blocks expire when the window ends.

#### Visit-Count Triggers
BrowserMonitor polls active browser URLs (via AppleScript). When visits to a URL pattern exceed the configured threshold, the blocklist activates for the configured duration.

## Development

- See `CHANGELOG.md` for current TODOs
- See `XPC_TODO.md` for planned XPC migration
- See `CLAUDE.md` for codebase guidance

### Build Commands

```bash
# Build in Xcode
# Select scheme (Willpower or WillpowerDaemon) then Cmd+B

# Build WillpowerKit package
cd WillpowerKit && swift build

# Run tests (when implemented)
cd WillpowerKit && swift test
```

## License

MIT License
