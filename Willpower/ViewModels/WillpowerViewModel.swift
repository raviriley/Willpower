//
//  WillpowerViewModel.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation
import WillpowerKit

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

    // MARK: - UI State

    var selectedCategory: SidebarCategory = .status
    var selectedBlocklistId: UUID?
    var isShowingNewBlocklistSheet: Bool = false
    var isShowingActivationSheet: Bool = false
    var errorMessage: String?
    var isLoading: Bool = false

    // MARK: - Private

    private let ipcManager: IPCManager
    private var syncTimer: Timer?

    /// Local storage key for blocklists (fallback when IPC unavailable)
    private let localBlocklistsKey = "willpower.local.blocklists"

    // MARK: - Initialization

    init(ipcManager: IPCManager = IPCManager()) {
        self.ipcManager = ipcManager
        self.isIPCAvailable = ipcManager.isAvailable

        // Load initial state from local storage
        loadLocalState()
    }

    // MARK: - Local Storage (Fallback)

    private func loadLocalState() {
        if let data = UserDefaults.standard.data(forKey: localBlocklistsKey),
           let saved = try? JSONDecoder().decode([BlocklistConfig].self, from: data) {
            blocklists = saved
        }
    }

    private func saveLocalState() {
        if let data = try? JSONEncoder().encode(blocklists) {
            UserDefaults.standard.set(data, forKey: localBlocklistsKey)
        }
    }

    // MARK: - State Synchronization

    /// Start polling for state updates from daemon
    nonisolated func startStateSync() {
        Task { @MainActor in
            syncState()

            syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncState()
                }
            }
        }
    }

    /// Stop state synchronization
    func stopStateSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    /// Sync state - only overwrite local if daemon is running
    func syncState() {
        // Check daemon status
        isDaemonRunning = ipcManager.isDaemonAlive(threshold: 15.0)
        lastDaemonHeartbeat = ipcManager.lastDaemonHeartbeat()

        // Only sync FROM daemon if it's actually running
        // This prevents empty IPC state from overwriting local blocklists
        if isDaemonRunning {
            let state = ipcManager.loadStateOrDefault()

            // Only update blocklists from daemon if daemon has data
            // or if we have no local data
            if !state.blocklists.isEmpty || blocklists.isEmpty {
                blocklists = state.blocklists
                saveLocalState() // Keep local storage in sync
            }

            activeBlocks = state.activeBlocks.filter { !$0.isExpired }
            visitRecords = state.visitRecords
            daemonVersion = state.daemonVersion
        } else {
            // Daemon not running - just ensure local state is loaded
            if blocklists.isEmpty {
                loadLocalState()
            }
            activeBlocks = []
            visitRecords = []
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
        } catch {
            errorMessage = "Failed to deactivate blocklist: \(error.localizedDescription)"
        }
    }

    // MARK: - Schedule Management

    /// Add a schedule trigger to a blocklist
    func addSchedule(to blocklist: BlocklistConfig, schedule: ScheduleBasedTrigger) {
        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return }

        let trigger = TriggerConfig.scheduleBased(schedule)
        updated.triggers.append(trigger)
        updateBlocklist(updated)
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

    // MARK: - Visit-Count Trigger Management

    /// Add a visit-count trigger to a blocklist
    func addVisitTrigger(to blocklist: BlocklistConfig, trigger: VisitCountTrigger) {
        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return }

        let config = TriggerConfig.visitCount(trigger)
        updated.triggers.append(config)
        updateBlocklist(updated)
    }

    /// Remove a visit-count trigger from a blocklist
    func removeVisitTrigger(triggerId: UUID, from blocklist: BlocklistConfig) {
        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return }
        updated.triggers.removeAll { $0.id == triggerId }
        updateBlocklist(updated)
    }

    /// Update an existing visit-count trigger
    func updateVisitTrigger(triggerId: UUID, in blocklist: BlocklistConfig, newTrigger: VisitCountTrigger) {
        guard var updated = blocklists.first(where: { $0.id == blocklist.id }) else { return }

        // Find and update the trigger
        if let idx = updated.triggers.firstIndex(where: { $0.id == triggerId }) {
            // Preserve the trigger ID and enabled state
            let wasEnabled = updated.triggers[idx].isEnabled
            // Create new trigger with same ID
            let updatedTrigger = TriggerConfig(
                id: triggerId,
                type: .visitCount,
                visitCount: newTrigger,
                isEnabled: wasEnabled
            )
            updated.triggers[idx] = updatedTrigger
            updateBlocklist(updated)
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

    /// Get visit-count triggers for a blocklist
    func visitCountTriggers(for blocklist: BlocklistConfig) -> [TriggerConfig] {
        blocklist.triggers.filter { $0.type == .visitCount }
    }

    /// All schedule triggers across all blocklists
    var allScheduleTriggers: [(blocklist: BlocklistConfig, trigger: TriggerConfig)] {
        blocklists.flatMap { blocklist in
            scheduleTriggers(for: blocklist).map { (blocklist, $0) }
        }
    }

    /// All visit-count triggers across all blocklists
    var allVisitCountTriggers: [(blocklist: BlocklistConfig, trigger: TriggerConfig)] {
        blocklists.flatMap { blocklist in
            visitCountTriggers(for: blocklist).map { (blocklist, $0) }
        }
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
