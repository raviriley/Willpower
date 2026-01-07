# Willpower - Changelog & Development TODOs

## Releases

### 1.0.2
- Fix error message persisting in onboarding after daemon is successfully running

### 1.0.1
- Shorten daemon status text in indicator

### 1.0.0
- Initial release

---

## Development TODOs

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
