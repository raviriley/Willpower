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

TODOs are organized into two phases:
- **Phase 1 (NOW)**: Core functionality, UX polish, making the app great
- **Phase 2 (LATER)**: Distribution, production infrastructure, post-launch features

---

## Phase 1: NOW - Core Features & Polish

### 1.1 Critical Functionality

#### Permissions & Setup
- [x] ~~**Accessibility permission for BrowserMonitor**~~ - **REMOVED**: Investigation revealed BrowserMonitor uses AppleScript, not Accessibility APIs. Accessibility permission is NOT required.

- [x] **Automation permission for AppleScript** - **ALREADY IMPLEMENTED**: macOS automatically prompts for Automation permission on first AppleScript execution. App has helper to open preferences if needed.

#### Enable/Disable Toggles
- [x] **Implement schedule/trigger enable toggle** - **ALREADY IMPLEMENTED**:
  - Independent triggers: Context menu toggle in TriggerListView
  - Schedules: TriggerConfig.isEnabled supported
  - Visual indicator: Gray icon when disabled
  - Functional: Browser monitoring respects isEnabled flag

### 1.2 UI/UX Polish

#### Performance
- [x] **Fix 5-second UI update lag** - **FIXED**: Added immediate `syncState()` calls after all IPC mutations:
  - Blocklist create/update/delete
  - Blocklist activate/deactivate
  - Independent trigger create/update/delete
  - Visit count reset

- [ ] **Reduce daemon evaluation interval** - Currently 5 seconds:
  - For schedules: 5 seconds is acceptable
  - For visit-count: Consider 1-2 seconds for more responsive blocking
  - Make configurable in daemon plist

#### Onboarding Flow
- [x] **First-launch onboarding** - **IMPLEMENTED**:
  - Step 1: Welcome screen explaining what Willpower does
  - Step 2: Daemon installation (SMAppService approval in System Settings)
  - Step 3: "Let's Go!" navigates to blocklists and opens create sheet
  - No "Later" buttons - must complete each step
  - Returning users with disabled daemon see only Step 2
  - State stored in UserDefaults

- [ ] **Permission status dashboard** - Show in Settings:
  - Daemon: Installed / Not Installed
  - Browser Automation: Shows which browsers have granted permission

#### Settings View
- [x] **Implement Settings view** - **IMPLEMENTED**:
  - **Status Section**: Protection status indicator, daemon last active timestamp, reinstall button
  - **Preferences Section**: Launch at login toggle (SMAppService.mainApp)
  - **Data Section**: Export/Import blocklists (JSON), Reset all data (blocked if locked blocks active)
  - **About Section**: App/daemon version, blocklist/trigger counts, GitHub link

#### Visual Design
- [ ] **App icon** - Replace default SwiftUI app icon
- [ ] **Color scheme refinement** - Consistent use of:
  - Green: active/protected
  - Orange: warning/pending
  - Red: blocked/error
  - Gray: disabled/inactive

- [x] **Empty states** - **IMPROVED**:
  - Blocklists: Explains grouping and automation benefits
  - Schedules: Highlights work hours, study, bedtime use cases
  - Triggers: Explains visit limiting for addictive sites

- [ ] **Loading states** - Show activity during:
  - Daemon communication
  - Blocklist activation
  - Permission checks

#### Interaction Polish
- [x] **Confirmation dialogs** - **IMPLEMENTED**:
  - Delete blocklist (warns about attached schedules)
  - Delete trigger (warns about visit history loss)
  - Deactivate unlocked block
  - Reset all data (in Settings)

- [ ] **Success feedback** - Visual confirmation when:
  - Blocklist created/updated
  - Block activated
  - Schedule saved

- [ ] **Error messages** - User-friendly errors:
  - "Daemon not running" → "Blocking is paused. Open Settings to reinstall."
  - Connection errors → "Reconnecting..." with retry

### 1.3 Core Feature Completion

#### Schedule Improvements
- [x] **Overnight schedule windows** - **FIXED**: Schedules spanning midnight now work:
  - TriggerEvaluator checks both "evening portion" (today) and "morning portion" (yesterday's overnight)
  - e.g., Thursday 22:00-05:00 correctly activates Friday morning
  - Also fixed: UI now shows per-schedule active status (not per-blocklist)

- [ ] **Schedule conflict detection** - Warn if schedules overlap:
  - Same blocklist, overlapping times
  - Show which schedules conflict

#### Blocklist Improvements
- [x] **Blocklist presets** - **IMPLEMENTED**:
  - Social Media: twitter, x, facebook, instagram, tiktok, snapchat, linkedin, threads
  - News & Reddit: reddit, HN, cnn, nytimes, bbc, foxnews, guardian, washingtonpost
  - Video Streaming: youtube, netflix, hulu, disney+, twitch, prime video, hbo, peacock
  - Gaming: steam, discord, twitch, epic, roblox, ea, battle.net
  - Shows in "Start from Template" section when creating new blocklist

- [x] **Domain validation** - **IMPLEMENTED**:
  - Strips protocols (http/https) and paths automatically
  - Strips www. prefix automatically
  - Validates domain format (must contain dot, valid characters only)
  - Shows inline error messages for invalid input
  - Prevents duplicate domains

- [ ] **Bulk domain add** - Paste multiple domains:
  - Support comma, newline, or space-separated
  - Show preview before adding

#### Daemon Communication
- [ ] **Heartbeat improvements** - More reliable daemon detection:
  - Current: 15-second threshold
  - Add "last seen" timestamp display
  - Show "Reconnecting..." state during brief disconnects

---

## Phase 2: LATER - Distribution & Infrastructure

### 2.1 Privileged Helper Architecture

#### SMAppService.daemon vs SMJobBless Decision

**Research Summary:**

| Aspect | SMAppService.daemon | SMJobBless |
|--------|---------------------|------------|
| macOS Version | 13+ (Ventura) | 10.6+ |
| Installation UX | User toggles switch in System Settings > Login Items | Single admin password prompt |
| Daemon Location | Inside app bundle (removed with app) | `/Library/PrivilegedHelperTools/` (persists) |
| Runs as Root | Yes (confirmed in Activity Monitor) | Yes |
| Apple Recommendation | Preferred for macOS 13+ | Deprecated |
| Complexity | Simpler setup | Complex Info.plist signing dance |
| Uninstall | Clean (removed with app) | Orphaned helpers remain |

**Recommendation: SMAppService.daemon**

Reasons:
1. Apple's recommended approach for macOS 13+ (our target is 15.6)
2. Daemon runs as root (required for `/etc/hosts`)
3. Clean uninstall - daemon removed with app
4. Simpler maintenance than SMJobBless
5. Future-proof (SMJobBless is deprecated)

The "toggle in System Settings" UX is less beneficial for tamper resistance - it's easier to find than killing a process. But that's a trade-off we are willing to make for the sake of simplicity.

**Implementation:**
- [x] **Migrate to SMAppService.daemon**:
  - [x] Move daemon binary to `Contents/MacOS/` or `Contents/Library/LaunchServices/`
  - [x] Create launchd plist at `Contents/Library/LaunchDaemons/`
  - [ ] Plist must include `BundleProgram`, `Label`, `MachServices` - MachServices not yet added (needed for XPC)
  - [x] Register with `SMAppService.daemon(plistName:).register()`
  - [x] Guide user to System Settings > Login Items to approve

- [ ] **XPC communication** - Replace file-based IPC:
  - [ ] Define XPC protocol for commands/state
  - [ ] Use `NSXPCConnection(machServiceName:)` for daemon communication
  - [ ] Add MachServices to launchd plist
  - More secure than file-based IPC
  - Plan documented in TODO.md

**References:**
- [SMAppService API Overview](https://theevilbit.github.io/posts/smappservice/)
- [HelperToolApp - SMAppService Example](https://github.com/alienator88/HelperToolApp)
- [Apple Forums: SMAppService with root Helper](https://developer.apple.com/forums/thread/733046)
- [macOS Apps With Embedded Daemons](https://dev.to/brysontyrrell/macos-apps-with-embedded-daemons-333a)

#### Daemon Tamper Resistance
- [x] **launchd KeepAlive** - Auto-restart if killed:
  - [x] Add `KeepAlive: true` to launchd plist
  - [x] Daemon restarts immediately if terminated via Activity Monitor
  - [x] Combined with locked blocks = robust protection

- [x] **Hide daemon from UI** - Core "willpower" principle:
  - [x] No "Stop Daemon" button anywhere
  - [x] Settings shows status only ("Protected")
  - [x] Only "Reinstall" for troubleshooting (buried)

- [ ] **Daemon version sync**:
  - Store version in daemon's Info.plist
  - App checks version on launch
  - If mismatch, prompt to re-approve in System Settings

### 2.2 IPC Architecture

- [x] ~~**Migrate to App Groups for production**~~ - App Groups don't work due to macl (Mandatory Access Control Label)

- [x] **File-based IPC implementation**:
  - [x] IPC at `/Library/Application Support/Willpower/ipc/` (system-wide, secure location)
  - [x] Three IPC files: state.json, commands.json, heartbeat
  - [x] Command deduplication prevents race conditions
  - [x] Stale command expiration (>30 seconds) prevents replay attacks

- [ ] **Migrate to XPC for production** - Plan documented in TODO.md, will do in a future release

- [x] **IPC security hardening** - **MOSTLY DONE**:
  - [x] Role-based file permissions (IPCRole enum distinguishes app vs daemon)
  - [x] Parent directory: 0o750 (owner rwx, admin group r-x)
  - [x] IPC directory: 0o770 (owner and admin group rwx)
  - [x] state.json: 0o640 (owner rw, admin group r)
  - [x] commands.json: 0o660 (owner and admin group rw)
  - [x] Admin group ownership (GID 80) enforced by daemon
  - [x] Blocklist existence validation before activation
  - [ ] Rate-limit commands
  - [ ] Use XPC audit tokens for caller verification - depends on XPC implementation

### 2.3 Code Signing & Distribution ✅

#### Code Signing
- [x] **Developer ID signing**:
  - [x] Sign main app with "Developer ID Application"
  - [x] Sign daemon with "Developer ID Application"
  - [x] Enable Hardened Runtime for both
  - [x] Inside-out signing for Sparkle framework (XPCs, Autoupdate, etc.)
  - [x] Automated via `scripts/codesign.sh`

#### Notarization
- [x] **Notarize for Gatekeeper**:
  - [x] Submit to Apple's notarization service
  - [x] Staple ticket to app bundle
  - [x] Automated via `scripts/notarize.sh`

#### Distribution
- [x] **Direct distribution (DMG)**:
  - [x] App Store not viable (privileged helper not allowed)
  - [x] Create DMG with drag-to-Applications via `scripts/create-dmg.sh`
  - [x] DMG signed and notarized
  - [x] Full release automation via `scripts/release.sh`

- [x] **Sparkle auto-updates**:
  - [x] Sparkle 2.8.1 integrated via SPM
  - [x] EdDSA signing keys in Keychain
  - [x] Appcast generation via `scripts/generate-appcast.sh`
  - [x] GitHub Releases hosting for DMG and appcast
  - [x] Full GitHub release automation via `scripts/github-release.sh`

- [ ] **Homebrew Cask** - For power users:
  - Create cask formula
  - Easy installation: `brew install --cask willpower`

### 2.4 Error Handling & Recovery

- [x] **Daemon crash recovery** - **PARTIAL**:
  - [x] launchd KeepAlive auto-restarts daemon if terminated
  - [x] Daemon loads current state from IPC files on startup
  - [ ] App shows "Reconnecting..." during brief disconnect
  - [x] If persistent failure, show "Reinstall" prompt

- [x] **State backup/recovery**:
  - [x] Backup state.json before each write
  - [x] Recover from backup on parse failure
  - [x] Never lose blocklist configurations

- [x] **Graceful degradation** - **PARTIAL**:
  - [x] App works for configuration even without daemon
  - [x] Clear indicator when blocking is inactive (heartbeat detection)
  - [x] Commands queued and sync to daemon when it becomes available
  - [ ] Show "Reconnecting..." UI state during brief disconnects

### 2.5 Security Hardening

- [ ] **Hosts file integrity**:
  - [ ] Verify managed section markers before modification
  - [ ] Detect external tampering
  - [ ] Alert user if /etc/hosts was modified outside app

- [x] **Command validation** - **PARTIAL**:
  - [x] UI-level domain validation (format, characters, strips protocols/www)
  - [x] UI-level URL pattern validation with regex support
  - [x] Blocklist existence check before activation (daemon)
  - [x] Empty command filtering to preserve state (daemon)
  - [ ] Daemon-level command parameter sanitization
  - [ ] Injection attack prevention at protocol level

### 2.6 Technical Debt

- [ ] **Unit tests** - Priority areas:
  - [ ] TriggerEvaluator schedule/visit logic
  - [ ] IPCManager serialization
  - [ ] HostsManager parsing
  - [ ] ViewModel state management

- [ ] **Integration tests**:
  - [ ] App → IPC → Daemon → hosts file flow
  - [ ] Schedule activation timing
  - [ ] Visit count threshold triggering

- [x] **Logging framework**:
  - [x] DaemonManager uses os_log with Logger class
  - [x] Created unified WillpowerLogger in WillpowerKit with subsystems/categories
  - [x] Created DaemonLogger for daemon with stdout fallback (for launchd capture)
  - [x] Replace print() with os_log in daemon
  - [x] Replace print() with os_log in WillpowerKit (IPCManager, HostsManager, PacketFilterManager, BrowserMonitor)
  - [x] Replace print() with os_log in app (WillpowerViewModel, SettingsView)
  - [x] Consistent log levels: debug, info, warning, error, fault

- [ ] **CI/CD pipeline**:
  - [ ] Automated builds
  - [ ] Run tests
  - [ ] Build notarized DMG for releases

---

## Phase 3: POST-LAUNCH - Feature Enhancements

- [ ] **Browser extension** - More accurate URL monitoring than AppleScript
- [ ] **Statistics dashboard** - Blocking history, visit counts over time, streaks
- [ ] **Blocklist import/export** - Share configurations
- [ ] **Focus mode integration** - Tie blocking to macOS Focus modes
- [ ] **iCloud sync** - Sync blocklists across devices
- [ ] **Menu bar status item** - Quick access without opening app
- [ ] **Widget support** - Show active blocks in Notification Center
- [ ] **Notifications** - Alert when block starts/ends
- [ ] **Keyboard shortcuts** - Quick activation from anywhere
- [ ] **Parental controls mode** - Password protection for settings
- [ ] **Emergency bypass** - Configurable "break glass" with cooling period

---

## Known Issues

1. ~~**Daemon must be manually installed**~~ - **FIXED**: Now uses SMAppService.daemon with System Settings approval
2. **First-time schedule evaluation** - May take up to 5 seconds for schedule to activate on creation
3. ~~**App Groups entitlement**~~ - **FIXED**: Removed unused entitlement; will use XPC in future release
4. **No state backup** - Risk of configuration loss if state.json becomes corrupted
5. ~~**Mixed logging**~~ - **FIXED**: Unified WillpowerLogger with os_log across entire codebase

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
