//
//  WillpowerViewModel.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation
import WillpowerKit
import AppKit

/// Sidebar navigation categories
enum SidebarCategory: String, CaseIterable, Identifiable {
    case status = "Status"
    case blocklists = "Blocklists"
    case schedules = "Schedules"
    case triggers = "Triggers"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .status: return "gauge.with.dots.needle.33percent"
        case .blocklists: return "list.bullet.rectangle"
        case .schedules: return "calendar.badge.clock"
        case .triggers: return "eye.trianglebadge.exclamationmark"
        case .settings: return "gear"
        }
    }
}

/// Central ViewModel managing all app state
/// Uses IPC when daemon is running, falls back to local storage otherwise
@MainActor
@Observable
final class WillpowerViewModel {

    // MARK: - State

    /// All configured blocklists
    var blocklists: [BlocklistConfig] = []

    /// Independent visit-count triggers (not attached to blocklists)
    var independentTriggers: [IndependentTrigger] = []

    /// Currently active blocks being enforced
    var activeBlocks: [ActiveBlock] = []

    /// Visit tracking records
    var visitRecords: [VisitRecord] = []

    /// Daemon status
    var isDaemonRunning: Bool = false
    var lastDaemonHeartbeat: Date?
    var daemonVersion: String?

    /// IPC availability
    var isIPCAvailable: Bool = false

    // MARK: - Browser Monitoring State

    /// Whether browser monitoring is active
    var isBrowserMonitoringActive: Bool = false

    /// Whether Automation permission is granted (needed for AppleScript)
    var hasAutomationPermission: Bool = false

    // MARK: - UI State

    var selectedCategory: SidebarCategory = .status
    var selectedBlocklistId: UUID?
    var isShowingActivationSheet: Bool = false
    var errorMessage: String?
    var isLoading: Bool = false
    
    // Cross-view navigation
    /// Pending schedule to edit (set before navigating to schedules)
    var pendingScheduleToEdit: (blocklist: BlocklistConfig, trigger: TriggerConfig)?
    /// Pending independent trigger to edit (set before navigating to triggers)
    var pendingTriggerToEdit: IndependentTrigger?

    // Detail pane selection
    /// Currently selected schedule (blocklist ID + trigger ID)
    var selectedScheduleId: (blocklistId: UUID, triggerId: UUID)?
    /// Currently selected independent trigger
    var selectedTriggerId: UUID?

    // MARK: - Private

    private let ipcManager: IPCManager
    private var syncTimer: Timer?
    private let browserMonitor: BrowserMonitor

    /// Local storage key for blocklists (fallback when IPC unavailable)
    private let localBlocklistsKey = "willpower.local.blocklists"
    /// Local storage key for independent triggers
    private let localTriggersKey = "willpower.local.triggers"

    // MARK: - Initialization

    init(ipcManager: IPCManager = IPCManager()) {
        self.ipcManager = ipcManager
        self.browserMonitor = BrowserMonitor()
        self.isIPCAvailable = ipcManager.isAvailable

        // Load initial state from local storage
        loadLocalState()

        // Setup browser monitor callback
        Task {
            await setupBrowserMonitorCallback()
        }
    }

    /// Setup the callback for when BrowserMonitor detects a pattern match
    private func setupBrowserMonitorCallback() async {
        await browserMonitor.setOnPatternMatch { [weak self] pattern, record in
            guard let self else { return }
            // Report visit to daemon via IPC
            do {
                try self.ipcManager.reportVisit(patternId: pattern.id, url: pattern.pattern)
                print("[WillpowerViewModel] Reported visit for pattern: \(pattern.pattern)")
            } catch {
                print("[WillpowerViewModel] Failed to report visit: \(error)")
            }
        }
    }

    // MARK: - Local Storage (Fallback)

    private func loadLocalState() {
        if let data = UserDefaults.standard.data(forKey: localBlocklistsKey),
           let saved = try? JSONDecoder().decode([BlocklistConfig].self, from: data) {
            blocklists = saved
        }
        if let data = UserDefaults.standard.data(forKey: localTriggersKey),
           let saved = try? JSONDecoder().decode([IndependentTrigger].self, from: data) {
            independentTriggers = saved
        }
    }

    private func saveLocalState() {
        if let data = try? JSONEncoder().encode(blocklists) {
            UserDefaults.standard.set(data, forKey: localBlocklistsKey)
        }
        if let data = try? JSONEncoder().encode(independentTriggers) {
            UserDefaults.standard.set(data, forKey: localTriggersKey)
        }
    }

    // MARK: - State Synchronization

    /// Start polling for state updates from daemon
    nonisolated func startStateSync() {
        Task { @MainActor in
            syncState()

            // Start browser monitoring if there are visit-count triggers
            if hasVisitCountTriggers {
                startBrowserMonitoring()
            }

            syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncState()
                }
            }
        }
    }

    /// Check if there are any enabled independent visit-count triggers
    private var hasVisitCountTriggers: Bool {
        independentTriggers.contains { $0.isEnabled }
    }

    /// Stop state synchronization
    func stopStateSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Browser Monitoring

    /// Start browser monitoring for visit-count triggers
    func startBrowserMonitoring() {
        Task {
            // Configure patterns from blocklists
            await configureBrowserMonitorPatterns()

            // Start monitoring
            await browserMonitor.startMonitoring()
            isBrowserMonitoringActive = await browserMonitor.isActive()
            print("[WillpowerViewModel] Browser monitoring started")
        }
    }

    /// Stop browser monitoring
    func stopBrowserMonitoring() {
        Task {
            await browserMonitor.stopMonitoring()
            isBrowserMonitoringActive = false
            print("[WillpowerViewModel] Browser monitoring stopped")
        }
    }

    /// Configure browser monitor with URL patterns from all independent triggers
    private func configureBrowserMonitorPatterns() async {
        var patterns: [URLPattern] = []

        for trigger in independentTriggers where trigger.isEnabled {
            patterns.append(contentsOf: trigger.urlPatterns)
        }

        await browserMonitor.setPatterns(patterns)
        print("[WillpowerViewModel] Configured browser monitor with \(patterns.count) pattern(s)")
    }

    /// Reconfigure browser monitor when blocklists change
    func reconfigureBrowserMonitor() {
        guard isBrowserMonitoringActive else { return }
        Task {
            await configureBrowserMonitorPatterns()
        }
    }

    // MARK: - Automation Permission

    /// Check if Automation permission is granted (needed for AppleScript browser access)
    /// Note: There's no direct API to check Automation permission - we detect it by attempting AppleScript
    func checkAutomationPermission() {
        // The first AppleScript execution will trigger the permission prompt
        // We can't directly check without triggering the prompt
        // For now, we assume it's granted if browser monitoring works
        hasAutomationPermission = true
    }

    /// Open System Preferences to Automation settings
    func openAutomationPreferences() {
        AccessibilityHelper.openAutomationPreferences()
    }

    /// Open System Preferences to Accessibility settings
    func openAccessibilityPreferences() {
        AccessibilityHelper.openAccessibilityPreferences()
    }

    /// Sync state from daemon - only syncs runtime state (active blocks, visits)
    /// Blocklists and triggers are managed locally and pushed TO daemon, never pulled FROM.
    func syncState() {
        // Check daemon status
        isDaemonRunning = ipcManager.isDaemonAlive(threshold: 15.0)
        lastDaemonHeartbeat = ipcManager.lastDaemonHeartbeat()

        // Only sync FROM daemon if it's actually running
        if isDaemonRunning {
            let state = ipcManager.loadStateOrDefault()

            // IMPORTANT: Don't sync blocklists/triggers FROM daemon!
            // The app is the source of truth. We push TO daemon, never pull FROM.
            // This prevents daemon's stale state from overwriting optimistic updates.

            // Only sync runtime state that daemon manages:
            activeBlocks = state.activeBlocks.filter { !$0.isExpired }
            visitRecords = state.visitRecords
            daemonVersion = state.daemonVersion
        } else {
            // Daemon not running - ensure local state is loaded
            if blocklists.isEmpty || independentTriggers.isEmpty {
                loadLocalState()
            }
            // Don't clear activeBlocks/visitRecords when daemon appears down briefly
            // This prevents UI flickering due to momentary heartbeat delays
            // The blocks will naturally expire based on their expiresAt time
        }
    }

    // MARK: - Blocklist CRUD

    /// Create a new blocklist
    func createBlocklist(name: String, domains: [String]) {
        let cleanedDomains = domains.map { cleanDomain($0) }.filter { !$0.isEmpty }
        let newBlocklist = BlocklistConfig(name: name, domains: cleanedDomains)

        // Update local state first
        blocklists.append(newBlocklist)
        selectedBlocklistId = newBlocklist.id
        saveLocalState()

        // Try to sync to IPC (best effort)
        syncBlocklistsToIPC()
    }

    /// Import a full blocklist (preserves triggers/schedules)
    func importBlocklist(_ blocklist: BlocklistConfig) {
        // Create new blocklist with fresh ID but preserve triggers
        var imported = BlocklistConfig(
            name: blocklist.name,
            domains: blocklist.domains.map { cleanDomain($0) }.filter { !$0.isEmpty }
        )
        imported.triggers = blocklist.triggers
        imported.isActive = false  // Don't auto-activate imported blocklists

        // Update local state first
        blocklists.append(imported)
        saveLocalState()

        // Try to sync to IPC (best effort)
        syncBlocklistsToIPC()
    }

    /// Update an existing blocklist
    func updateBlocklist(_ blocklist: BlocklistConfig) {
        guard let index = blocklists.firstIndex(where: { $0.id == blocklist.id }) else { return }

        var updated = blocklist
        updated.updatedAt = Date()

        // Update local state first
        blocklists[index] = updated
        saveLocalState()

        // Try to sync to IPC
        syncBlocklistsToIPC()
    }

    /// Delete a blocklist
    func deleteBlocklist(_ blocklist: BlocklistConfig) {
        if let activeBlock = activeBlocks.first(where: { $0.blocklistId == blocklist.id }),
           activeBlock.isLocked && !activeBlock.isExpired {
            errorMessage = "Cannot delete blocklist with active locked block"
            return
        }

        // Update local state first
        blocklists.removeAll { $0.id == blocklist.id }
        if selectedBlocklistId == blocklist.id {
            selectedBlocklistId = nil
        }
        saveLocalState()

        // Try to sync to IPC
        syncBlocklistsToIPC()
    }

    /// Sync current blocklists to IPC (best effort, doesn't fail UI)
    private func syncBlocklistsToIPC() {
        do {
            try ipcManager.updateBlocklists(blocklists)
            // Also reconfigure browser monitor with new patterns
            reconfigureBrowserMonitor()
            // Note: Don't call syncState() here - it would read stale daemon state
            // and overwrite our optimistic local update. The polling timer handles sync.
        } catch {
            // Log but don't show error to user - local state is saved
            print("[WillpowerViewModel] IPC sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Activation

    /// Activate a blocklist for a duration
    func activateBlocklist(_ blocklist: BlocklistConfig, durationSeconds: Int, isLocked: Bool = true) {
        guard isDaemonRunning else {
            errorMessage = "Cannot activate blocklist: Daemon is not running. Start the daemon with sudo first."
            return
        }

        let trigger = TriggerConfig.timeBased(
            TimeBasedTrigger(durationSeconds: durationSeconds)
        )

        do {
            try ipcManager.activateBlocklist(blocklist.id, trigger: trigger, isLocked: isLocked)
            // Force immediate state sync to reflect activation
            syncState()
        } catch {
            errorMessage = "Failed to activate blocklist: \(error.localizedDescription)"
        }
    }

    /// Deactivate a blocklist (will fail if locked)
    func deactivateBlocklist(_ blocklist: BlocklistConfig) {
        guard isDaemonRunning else {
            errorMessage = "Cannot deactivate blocklist: Daemon is not running"
            return
        }

        do {
            try ipcManager.deactivateBlocklist(blocklist.id)
            // Force immediate state sync to reflect deactivation
            syncState()
        } catch {
            errorMessage = "Failed to deactivate blocklist: \(error.localizedDescription)"
        }
    }

    // MARK: - Schedule Management

    /// Add a schedule trigger to a blocklist
    @discardableResult
    func addSchedule(to blocklist: BlocklistConfig, schedule: ScheduleBasedTrigger) -> UUID {
        let trigger = TriggerConfig.scheduleBased(schedule)

        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return trigger.id }

        updated.triggers.append(trigger)
        updateBlocklist(updated)
        return trigger.id
    }

    /// Remove a schedule trigger from a blocklist
    func removeSchedule(triggerId: UUID, from blocklist: BlocklistConfig) {
        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return }
        updated.triggers.removeAll { $0.id == triggerId }
        updateBlocklist(updated)
    }

    /// Update an existing schedule trigger
    func updateSchedule(triggerId: UUID, in blocklist: BlocklistConfig, newSchedule: ScheduleBasedTrigger) {
        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return }

        // Find and update the trigger
        if let idx = updated.triggers.firstIndex(where: { $0.id == triggerId }) {
            // Preserve the trigger ID and enabled state
            let wasEnabled = updated.triggers[idx].isEnabled
            // Create new trigger with same ID
            let newTrigger = TriggerConfig(
                id: triggerId,
                type: .scheduleBased,
                scheduleBased: newSchedule,
                isEnabled: wasEnabled
            )
            updated.triggers[idx] = newTrigger
            updateBlocklist(updated)
        }
    }

    // MARK: - Independent Trigger Management

    /// Create a new independent trigger
    func createIndependentTrigger(_ trigger: IndependentTrigger) {
        // Update local state first
        independentTriggers.append(trigger)
        saveLocalState()

        // Try to sync to IPC (best effort)
        syncTriggersToIPC()

        // Reconfigure browser monitor with new patterns
        reconfigureBrowserMonitor()

        // Start browser monitoring if not already running
        if !isBrowserMonitoringActive && trigger.isEnabled {
            startBrowserMonitoring()
        }
    }

    /// Update an existing independent trigger
    func updateIndependentTrigger(_ trigger: IndependentTrigger) {
        guard let index = independentTriggers.firstIndex(where: { $0.id == trigger.id }) else { return }

        var updated = trigger
        updated.updatedAt = Date()

        // Update local state first
        independentTriggers[index] = updated
        saveLocalState()

        // Try to sync to IPC
        syncTriggersToIPC()

        // Reconfigure browser monitor with updated patterns
        reconfigureBrowserMonitor()
    }

    /// Delete an independent trigger
    func deleteIndependentTrigger(_ trigger: IndependentTrigger) {
        // Update local state first (optimistic update)
        independentTriggers.removeAll { $0.id == trigger.id }
        saveLocalState()

        // Try to sync to IPC
        do {
            try ipcManager.deleteIndependentTrigger(triggerId: trigger.id)
            // Note: Don't call syncState() here - it would read stale daemon state
        } catch {
            print("[WillpowerViewModel] IPC delete trigger failed: \(error.localizedDescription)")
        }

        // Reconfigure browser monitor
        reconfigureBrowserMonitor()

        // Stop browser monitoring if no more triggers
        if independentTriggers.isEmpty {
            stopBrowserMonitoring()
        }
    }

    /// Sync current independent triggers to IPC (best effort, doesn't fail UI)
    private func syncTriggersToIPC() {
        do {
            try ipcManager.updateIndependentTriggers(independentTriggers)
            // Note: Don't call syncState() here - it would read stale daemon state
            // and overwrite our optimistic local update. The polling timer handles sync.
        } catch {
            // Log but don't show error to user - local state is saved
            print("[WillpowerViewModel] IPC trigger sync failed: \(error.localizedDescription)")
        }
    }

    /// Reset visit counts
    func resetVisitCounts(patternIds: [UUID]? = nil) {
        guard isDaemonRunning else {
            errorMessage = "Cannot reset visit counts: Daemon is not running"
            return
        }

        do {
            try ipcManager.resetVisitCounts(patternIds: patternIds)
            // Force immediate state sync to reflect reset
            syncState()
        } catch {
            errorMessage = "Failed to reset visit counts: \(error.localizedDescription)"
        }
    }

    // MARK: - Computed Properties

    /// Get currently selected blocklist
    var selectedBlocklist: BlocklistConfig? {
        guard let id = selectedBlocklistId else { return nil }
        return blocklists.first { $0.id == id }
    }

    /// Get currently selected schedule (blocklist + trigger)
    var selectedSchedule: (blocklist: BlocklistConfig, trigger: TriggerConfig)? {
        guard let ids = selectedScheduleId,
              let blocklist = blocklists.first(where: { $0.id == ids.blocklistId }),
              let trigger = blocklist.triggers.first(where: { $0.id == ids.triggerId }) else {
            return nil
        }
        return (blocklist, trigger)
    }

    /// Get currently selected independent trigger
    var selectedTrigger: IndependentTrigger? {
        guard let id = selectedTriggerId else { return nil }
        return independentTriggers.first { $0.id == id }
    }

    /// Get active block for a blocklist
    func activeBlock(for blocklist: BlocklistConfig) -> ActiveBlock? {
        activeBlocks.first { $0.blocklistId == blocklist.id && !$0.isExpired }
    }

    /// Check if blocklist is currently active
    func isBlocklistActive(_ blocklist: BlocklistConfig) -> Bool {
        activeBlock(for: blocklist) != nil
    }

    /// Check if blocklist has a locked block
    func isBlocklistLocked(_ blocklist: BlocklistConfig) -> Bool {
        guard let block = activeBlock(for: blocklist) else { return false }
        return block.isLocked
    }

    /// Total unique domains being blocked
    var totalDomainsBlocked: Int {
        Set(activeBlocks.flatMap { $0.domains }).count
    }

    /// Get schedule triggers for a blocklist
    func scheduleTriggers(for blocklist: BlocklistConfig) -> [TriggerConfig] {
        blocklist.triggers.filter { $0.type == .scheduleBased }
    }

    /// All schedule triggers across all blocklists
    var allScheduleTriggers: [(blocklist: BlocklistConfig, trigger: TriggerConfig)] {
        blocklists.flatMap { blocklist in
            scheduleTriggers(for: blocklist).map { (blocklist, $0) }
        }
    }

    /// All enabled independent triggers
    var allIndependentTriggers: [IndependentTrigger] {
        independentTriggers
    }

    // MARK: - Helpers

    /// Clean a domain string
    private func cleanDomain(_ input: String) -> String {
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
        if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
        if let slash = cleaned.firstIndex(of: "/") { cleaned = String(cleaned[..<slash]) }
        return cleaned
    }

    /// Clear error message
    func clearError() {
        errorMessage = nil
    }
}
