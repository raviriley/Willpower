## Build from Source

1. Clone the repository
2. Open `Willpower.xcodeproj` in Xcode
3. Select the `Willpower` scheme
4. Build and Run (Cmd+R)

## First Launch

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

## Privilege Separation

- **Willpower/** - Sandboxed SwiftUI app (UI/configuration)
- **WillpowerDaemon/** - Root daemon (enforces blocking via SMAppService.daemon)
- **WillpowerKit/** - Shared Swift package (models, blocking logic)

## IPC Flow

```
[App] → /Library/Application Support/Willpower/ipc/commands.json → [Daemon]
[Daemon] → /Library/Application Support/Willpower/ipc/state.json → [App]
[Daemon] → /Library/Application Support/Willpower/ipc/heartbeat → [App] (liveness check)
```

## Key Behaviors

### Locked Blocks
When a blocklist is activated with `isLocked: true`, it cannot be deactivated until expiration. This is the "willpower" in Willpower - users can't bypass their own blocks.

### Add-Only Domain Editing
Active blocklists can have domains added (immediately blocked), but existing domains cannot be removed until the block expires. Prevents circumventing blocks by deleting domains.

### Schedule Activation
Daemon evaluates schedule triggers every 5 seconds. When the current time falls within a schedule window, the blocklist activates. Schedule blocks expire when the window ends.

### Visit-Count Triggers
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

----------

# Development TODOs

## Phase 1: Core Features & Polish

### Performance
- [ ] Reduce daemon evaluation interval (currently 5 seconds, consider 1-2 seconds for visit-count triggers)

### UI/UX
- [ ] App icon - Replace default SwiftUI app icon
- [ ] Color scheme refinement - Consistent use of green (active), orange (warning), red (blocked), gray (inactive)
- [ ] Loading states during daemon communication, blocklist activation, permission checks
- [ ] Success feedback when blocklist created/updated, block activated, schedule saved
- [ ] Error messages - User-friendly errors with actionable guidance
- [ ] Permission status dashboard in Settings showing daemon and browser automation status

### Features
- [ ] Schedule conflict detection - Warn when schedules overlap for the same blocklist
- [ ] Bulk domain add - Support comma, newline, or space-separated paste with preview
- [ ] Heartbeat improvements - Show "last seen" timestamp, "Reconnecting..." state during brief disconnects

---

## Phase 2: Distribution & Infrastructure

### Daemon Architecture
- [ ] XPC communication - Replace file-based IPC with XPC Mach service (see `XPC_TODO.md`)
- [ ] Daemon version sync - Check version on launch, prompt to re-approve if mismatch
- [ ] Rate-limit IPC commands

### Distribution
- [ ] Homebrew Cask formula for easy installation

### Security
- [ ] Hosts file integrity verification - Detect external tampering
- [ ] Command parameter sanitization at daemon level
- [ ] Injection attack prevention at protocol level

### Testing & CI
- [ ] Unit tests for TriggerEvaluator, IPCManager, HostsManager, ViewModel
- [ ] Integration tests for app → IPC → daemon → hosts file flow
- [ ] CI/CD pipeline with automated builds and notarized DMG releases

---

## Phase 3: Future Features

- [ ] Browser extension for more accurate URL monitoring
- [ ] Statistics dashboard - Blocking history, visit counts over time, streaks
- [ ] Focus mode integration - Tie blocking to macOS Focus modes
- [ ] iCloud sync - Sync blocklists across devices
- [ ] Menu bar status item - Quick access without opening app
- [ ] Widget support - Show active blocks in Notification Center
- [ ] Notifications - Alert when block starts/ends
- [ ] Keyboard shortcuts - Quick activation from anywhere
- [ ] Parental controls mode - Password protection for settings
- [ ] Emergency bypass - Configurable "break glass" with cooling period

---

## Testing Checklist

- [ ] Test overnight schedule windows (e.g., 22:00-05:00)
- [ ] Test visit-count threshold activation
- [ ] Test daemon restart recovery


## Daemon reliability verification

`swift test --package-path WillpowerKit` covers missing executables, nonzero exits,
command timeouts, and output larger than a pipe buffer. System commands have a
five-second deadline (two seconds for each DNS cache command). Firewall DNS work
runs separately from the five-second schedule/heartbeat loop.

For a signed build installed at its permanent location, check:

- Reinstall once while online and once while offline. The spinner should remain
  until a new heartbeat arrives, approval is required, or a specific error appears.
- Disable background approval, then retry. The app should direct you to Login Items.
- Sleep/wake and temporarily disconnect the network with schedules active. Hosts
  blocking and heartbeat should continue independently of firewall DNS resolution.
- Stop the daemon and let launchd restart it. If an approved service stays offline,
  the app attempts repair after 60 seconds, at most once per five minutes.
- Close the window, reopen from Dock and menu bar, and repeat quickly. Only one
  main window should appear.

The unsigned build and package tests cannot verify privileged service registration
or System Settings approval. Install a signed app and reinstall its background
service once to load these daemon changes; building alone does not replace the
running service.
