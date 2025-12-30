# Willpower - Development Session Summary

## Session Date: December 30, 2025

This document summarizes the major changes made during this development session for the Willpower macOS website blocker app.

---

## Overview

Willpower is a macOS website blocker that uses `/etc/hosts` manipulation via a privileged daemon. This session implemented the complete SwiftUI app interface and fixed critical daemon issues.

---

## Commits Made (8 total)

### 1. Add SwiftUI app with MVVM architecture and navigation
- Restructured app with three-column `NavigationSplitView`
- Created `WillpowerViewModel` as central state manager with IPC sync
- Built sidebar navigation: Status, Blocklists, Schedules, Triggers, Settings
- Added status dashboard showing active blocks with countdown timers
- Created reusable components: `DaemonStatusIndicator`, `TimeRemainingView`, `StatusBadge`

### 2. Add daemon management and launchd integration
- Created `DaemonManager` for LaunchDaemon registration/unregistration
- Built `DaemonSetupView` for guided daemon installation
- Added launchd plist for daemon auto-start at boot
- Support both SMAppService API and manual launchctl fallback

### 3. Improve IPC with file-based communication and command deduplication
- Switched to file-based IPC at `/tmp/willpower` (from App Groups only)
- Enables cross-privilege communication between sandboxed app and root daemon
- Added command deduplication to prevent `updateBlocklists` queue buildup
- Set appropriate permissions for user-app to root-daemon access

### 4. Fix daemon command processing and schedule evaluation
- Added stale command expiration (>30 seconds) to prevent replay attacks
- Validate blocklist exists before processing `activateBlocklist` commands
- Guard against empty `updateBlocklists` clearing existing state
- Clean up orphaned active blocks when blocklists are deleted
- Add-only domain sync for active blocklists (can add domains, not remove)
- **Fixed critical bug:** Schedule triggers were being skipped (only visit-count evaluated)

### 5. Add DNS cache flush after hosts file changes
- Added `flushDNSCache()` using `dscacheutil -flushcache`
- Also restarts mDNSResponder for complete cache invalidation
- Blocking takes effect immediately without manual intervention

### 6. Add blocklist management UI with manual activation
- `BlocklistListView` with create/edit/delete operations
- `BlocklistDetailView` showing domains and active block status
- `BlocklistEditorSheet` for domain management
- `ManualActivationSheet` with duration picker and lock option
- Add-only domain editing while blocklist is active (locked domains show lock icon)

### 7. Add editable schedule-based blocking
- `ScheduleListView` displaying triggers grouped by blocklist
- `ScheduleEditorSheet` for creating/editing schedules
- `WeekdayPicker` component for day selection
- Multiple time windows per schedule supported
- Active status indicator with green checkmark
- Warning banner when editing active schedule

### 8. Add editable visit-count triggers
- `TriggerListView` displaying triggers with visit progress
- `TriggerEditorSheet` for URL pattern configuration
- Color-coded visit count badges (green → yellow → orange → red)
- Configure max visits, block duration, reset interval
- Warning banner when editing active trigger

---

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
    ├── BrowserMonitor.swift    # URL polling
    └── TriggerEvaluator.swift  # Schedule/visit evaluation
```

---

## IPC Flow

```
[App] → /tmp/willpower/commands.json → [Daemon]
[Daemon] → /tmp/willpower/state.json → [App]
[Daemon] → /tmp/willpower/heartbeat → [App] (liveness check)
```

---

## Key Behaviors

### Locked Blocks
- When a blocklist is activated with `isLocked: true`, it cannot be deactivated until expiration
- This is the "willpower" in Willpower - users can't bypass their own blocks

### Add-Only Domain Editing
- Active blocklists can have domains added (immediately blocked)
- Existing domains cannot be removed until the block expires
- Prevents circumventing blocks by deleting domains

### Schedule Activation
- Daemon evaluates schedule triggers every 5 seconds
- When current time falls within a schedule window, blocklist activates
- Schedule blocks expire when the window ends

### Visit-Count Triggers
- BrowserMonitor polls active browser URLs
- Matches against configured URL patterns
- When threshold exceeded, blocklist activates for configured duration

---

## TODOs

### High Priority

- [ ] **Enable/disable toggle for schedules and triggers** - Currently toggles are disabled with TODO comment
- [ ] **Settings view implementation** - Settings category exists in sidebar but view is placeholder
- [ ] **Error handling UI improvements** - Show more specific error messages for daemon communication failures
- [ ] **Persist daemon status across app launches** - Currently requires manual re-registration if daemon stops

### Medium Priority

- [ ] **Overnight schedule windows** - Test and validate schedules spanning midnight (e.g., 22:00-06:00)
- [ ] **Browser monitor accuracy** - Current polling may miss rapid page navigation
- [ ] **Visit count persistence** - Visit records should survive daemon restarts
- [ ] **Multiple schedules per blocklist** - UI supports this but needs testing
- [ ] **Blocklist import/export** - Allow users to share blocklist configurations
- [ ] **Menu bar quick actions** - Mini status and quick activation from menu bar

### Low Priority / Future Features

- [ ] **App Sandbox compliance** - Currently requires disabling sandbox for /tmp access
- [ ] **Code signing for distribution** - Proper signing for LaunchDaemon installation
- [ ] **Focus mode integration** - Tie blocking to macOS Focus modes
- [ ] **Statistics dashboard** - Show blocking history, visit counts over time
- [ ] **Parental controls mode** - Password protection for settings
- [ ] **Browser extension** - More accurate URL monitoring than polling
- [ ] **iCloud sync** - Sync blocklists across devices
- [ ] **Widget support** - Show active blocks in Notification Center

### Technical Debt

- [ ] **Unit tests** - No test coverage currently
- [ ] **SwiftData integration** - Consider migrating from UserDefaults for persistence
- [ ] **Logging framework** - Replace print statements with proper logging
- [ ] **Documentation** - Code documentation and user guide
- [ ] **Info.plist configuration** - Fix PRODUCT_BUNDLE_IDENTIFIER warning for daemon

---

## Known Issues

1. **Daemon must be manually installed** - Requires copying binary and running launchctl commands
2. **First-time schedule evaluation** - May take up to 5 seconds for schedule to activate on creation
3. **App Groups entitlement** - Currently unused but entitlement remains in project

---

## Testing Checklist

- [x] Create blocklist with domains
- [x] Activate blocklist with timer
- [x] Verify /etc/hosts is modified
- [x] Verify domains are blocked in browser
- [x] Wait for expiration and verify unblock
- [x] Create schedule trigger
- [x] Verify schedule activates at correct time
- [x] Edit schedule while not active
- [x] Create visit-count trigger
- [x] Add domains to active blocklist
- [ ] Test overnight schedule windows
- [ ] Test visit-count threshold activation
- [ ] Test daemon restart recovery
