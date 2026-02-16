import Foundation
import WillpowerKit

// MARK: - Configuration

private let daemonVersion = "1.0.5"  // Allow list support
private let runLoopInterval: TimeInterval = 5.0
private let heartbeatInterval: TimeInterval = 5.0

// MARK: - Logging

/// Unified daemon logger using os_log with stdout fallback for launchd
private let log = DaemonLogger()

// MARK: - Main Entry Point

log.info("Starting v\(daemonVersion)...")
log.info("PID: \(getpid()), UID: \(getuid())")

// Check if running as root (required for /etc/hosts modification)
if getuid() != 0 {
    log.warning("Not running as root (UID: \(getuid()))")
    log.warning("/etc/hosts modification will fail without root privileges")
    log.warning("Run with sudo or install as LaunchDaemon")
}

// MARK: - IPC Setup

// Log the IPC directory being used
// Using /Library/Application Support/Willpower/ipc - accessible by both root and user
log.info("IPC directory: \(IPCManager.ipcDirectory)")

let fm = FileManager.default

// Ensure IPC directory exists with proper permissions
// Using /Library/Application Support/Willpower/ipc which is accessible by both root and user
let ipcDir = IPCManager.ipcDirectory
let parentDir = "/Library/Application Support/Willpower"

// Admin group ID for file ownership
let adminGroupID: UInt32 = 80  // 'admin' group on macOS

if !fm.fileExists(atPath: parentDir) {
    do {
        try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        // 0o750: owner (root) rwx, group (admin) r-x, others ---
        try fm.setAttributes([.posixPermissions: 0o750, .groupOwnerAccountID: adminGroupID], ofItemAtPath: parentDir)
        log.info("Created parent directory: \(parentDir)")
    } catch {
        log.error("Failed to create parent directory: \(error)")
    }
}

if !fm.fileExists(atPath: ipcDir) {
    do {
        try fm.createDirectory(atPath: ipcDir, withIntermediateDirectories: true)
        // 0o770: owner (root) rwx, group (admin) rwx, others ---
        try fm.setAttributes([.posixPermissions: 0o770, .groupOwnerAccountID: adminGroupID], ofItemAtPath: ipcDir)
        log.info("Created IPC directory: \(ipcDir)")
    } catch {
        log.error("Failed to create IPC directory: \(error)")
    }
}

// Initialize components
let hostsManager = HostsManager()
let packetFilterManager = PacketFilterManager()
let ipcManager = IPCManager(role: .daemon)  // Use daemon role for tighter permissions
let triggerEvaluator = TriggerEvaluator()

/// Track previous blocked/allowed domains to detect changes (must be before dispatchMain)
/// nil = never synced (force initial sync), empty = synced with no domains
var previousBlockedDomains: Set<String>?
var previousAllowedDomains: Set<String>?

// NOTE: BrowserMonitor runs in the app, not the daemon.
// The daemon runs as root and doesn't have access to user's GUI session
// or Automation permissions needed for AppleScript browser monitoring.
// The app reports visits via IPC using the .reportVisit command.

// Check IPC availability
guard ipcManager.isAvailable else {
    log.fault("IPC not available - ensure directory permissions are correct")
    exit(1)
}

// Load initial state or create default
var state = ipcManager.loadStateOrDefault()
state.daemonVersion = daemonVersion
log.info("Loaded state: \(state.blocklists.count) blocklists, \(state.activeBlocks.count) active blocks")

// Start async operations
Task {
    log.info("Initialized. Entering run loop...")

    // Main run loop
    var lastHeartbeat = Date()

    while true {
        do {
            let now = Date()

            // Update heartbeat periodically
            if now.timeIntervalSince(lastHeartbeat) >= heartbeatInterval {
                ipcManager.updateDaemonHeartbeat()
                lastHeartbeat = now
            }

            // Process pending commands from app (includes visit reports)
            // Returns updated state and whether configuration changed (blocklists/triggers)
            let (updatedState, configChanged) = try await processCommands(
                ipcManager: ipcManager,
                state: state
            )
            state = updatedState

            // Evaluate triggers and update blocks
            state = evaluateTriggers(
                state: state,
                triggerEvaluator: triggerEvaluator
            )

            // Clean up expired blocks
            state = cleanupExpiredBlocks(state: state)

            // Apply dual-layer blocking (hosts file + pf firewall)
            try applyBlocks(
                state: state,
                hostsManager: hostsManager,
                packetFilterManager: packetFilterManager
            )

            // Save state (backup only when config changed to preserve blocklist/trigger data)
            try ipcManager.saveState(state, backupFirst: configChanged)

        } catch {
            log.error("Error in run loop: \(error)")
        }

        // Sleep until next iteration
        try? await Task.sleep(nanoseconds: UInt64(runLoopInterval * 1_000_000_000))
    }
}

// Keep the process alive
dispatchMain()

// MARK: - Command Processing

/// Process pending commands and return updated state with config change flag
/// - Returns: Tuple of (updatedState, configurationChanged)
///   configurationChanged is true when blocklists or triggers are modified (create/update/delete)
func processCommands(
    ipcManager: IPCManager,
    state: WillpowerState
) async throws -> (WillpowerState, Bool) {
    var mutableState = state
    var configChanged = false  // Track if blocklists/triggers changed
    let commands = try ipcManager.loadPendingCommands()

    guard !commands.isEmpty else { return (state, false) }

    log.info("Processing \(commands.count) command(s)")

    for wrapper in commands {
        // Skip stale commands older than 30 seconds to prevent replay of old commands
        let commandAge = Date().timeIntervalSince(wrapper.timestamp)
        if commandAge > 30 {
            log.debug("SKIPPED: Stale command (age: \(Int(commandAge))s) - \(wrapper.command)")
            try ipcManager.markCommandProcessed(wrapper.id)
            continue
        }

        log.debug("Command: \(wrapper.command)")

        switch wrapper.command {
        case .activateBlocklist(let blocklistId, let trigger, let isLocked):
            // VALIDATE: Only activate if blocklist exists in current state
            guard mutableState.blocklists.contains(where: { $0.id == blocklistId }) else {
                log.warning("SKIPPED: activateBlocklist for non-existent blocklist \(blocklistId)")
                break
            }
            mutableState = activateBlocklist(
                blocklistId,
                trigger: trigger,
                isLocked: isLocked,
                state: mutableState
            )

        case .deactivateBlocklist(let blocklistId):
            mutableState = deactivateBlocklist(blocklistId, state: mutableState)

        case .updateBlocklists(let blocklists):
            // GUARD: Don't process empty updates if we have existing data
            // This prevents race conditions from clearing state
            if blocklists.isEmpty && !mutableState.blocklists.isEmpty {
                log.debug("SKIPPED: updateBlocklists with empty array (preserving existing \(mutableState.blocklists.count) blocklists)")
                break
            }

            mutableState.blocklists = blocklists
            mutableState.lastUpdated = Date()
            configChanged = true  // Blocklists modified - backup needed

            // Clean up orphaned active blocks (blocks for deleted blocklists)
            // NOTE: Skip blocks from independent visit-count triggers - they use pattern.id as blocklistId
            let validBlocklistIds = Set(blocklists.map { $0.id })
            let orphanedBlocks = mutableState.activeBlocks.filter { block in
                // Don't consider visit-count trigger blocks as orphaned
                // They use pattern.id as blocklistId, not an actual blocklist ID
                guard block.reason != .visitCountTrigger else { return false }
                return !validBlocklistIds.contains(block.blocklistId)
            }

            if !orphanedBlocks.isEmpty {
                log.info("Cleaning up \(orphanedBlocks.count) orphaned active block(s)")
                mutableState.activeBlocks.removeAll { block in
                    guard block.reason != .visitCountTrigger else { return false }
                    return !validBlocklistIds.contains(block.blocklistId)
                }
            }

            // Sync NEW domains to active blocks (add-only, never remove)
            // This allows users to add domains to active blocklists
            for (blockIdx, activeBlock) in mutableState.activeBlocks.enumerated() {
                if let updatedBlocklist = blocklists.first(where: { $0.id == activeBlock.blocklistId }) {
                    let currentDomains = Set(activeBlock.domains)
                    let updatedDomains = Set(updatedBlocklist.domains)
                    let newDomains = updatedDomains.subtracting(currentDomains)

                    if !newDomains.isEmpty {
                        log.info("Adding \(newDomains.count) new domain(s) to active block for '\(updatedBlocklist.name)'")
                        mutableState.activeBlocks[blockIdx].domains.append(contentsOf: newDomains)
                    }
                }
            }

        case .forceSync:
            mutableState.lastUpdated = Date()

        case .reportVisit(let patternId, let url):
            // Visit reported from app (which runs BrowserMonitor)
            if let idx = mutableState.visitRecords.firstIndex(where: { $0.patternId == patternId }) {
                mutableState.visitRecords[idx].recordVisit()
                log.debug("Visit recorded for pattern \(patternId): count=\(mutableState.visitRecords[idx].visitCount)")
            } else {
                // Create new visit record if it doesn't exist
                // Find the pattern string from independent triggers first
                var patternString = url
                for trigger in mutableState.independentTriggers {
                    if let pattern = trigger.urlPatterns.first(where: { $0.id == patternId }) {
                        patternString = pattern.pattern
                        break
                    }
                }
                // Fall back to blocklist triggers (legacy)
                if patternString == url {
                    for blocklist in mutableState.blocklists {
                        for trigger in blocklist.triggers where trigger.type == .visitCount {
                            if let vc = trigger.visitCount,
                               let pattern = vc.urlPatterns.first(where: { $0.id == patternId }) {
                                patternString = pattern.pattern
                                break
                            }
                        }
                    }
                }
                var record = VisitRecord(patternId: patternId, pattern: patternString)
                record.recordVisit()
                mutableState.visitRecords.append(record)
                log.debug("New visit record created for pattern \(patternId)")
            }
            mutableState.lastUpdated = Date()

        case .updateIndependentTriggers(let triggers):
            // GUARD: Don't process empty updates if we have existing data
            if triggers.isEmpty && !mutableState.independentTriggers.isEmpty {
                log.debug("SKIPPED: updateIndependentTriggers with empty array (preserving existing \(mutableState.independentTriggers.count) triggers)")
                break
            }
            mutableState.independentTriggers = triggers
            mutableState.lastUpdated = Date()
            configChanged = true  // Triggers modified - backup needed
            log.info("Updated independent triggers: \(triggers.count) trigger(s)")

        case .deleteIndependentTrigger(let triggerId):
            let beforeCount = mutableState.independentTriggers.count
            mutableState.independentTriggers.removeAll { $0.id == triggerId }
            if beforeCount > mutableState.independentTriggers.count {
                log.info("Deleted independent trigger \(triggerId)")
                configChanged = true  // Trigger deleted - backup needed
            }
            mutableState.lastUpdated = Date()
        }

        try ipcManager.markCommandProcessed(wrapper.id)
    }

    return (mutableState, configChanged)
}

// MARK: - Blocklist Activation

func activateBlocklist(
    _ blocklistId: UUID,
    trigger: TriggerConfig?,
    isLocked: Bool,
    state: WillpowerState
) -> WillpowerState {
    var mutableState = state

    guard let blocklistIdx = mutableState.blocklists.firstIndex(where: { $0.id == blocklistId }) else {
        log.warning("Blocklist not found: \(blocklistId)")
        return state
    }

    let blocklist = mutableState.blocklists[blocklistIdx]

    // Check if already has an active locked block
    if let existingBlock = mutableState.activeBlocks.first(where: { $0.blocklistId == blocklistId }),
       existingBlock.isLocked && !existingBlock.isExpired {
        log.debug("Blocklist already has active locked block until \(existingBlock.expiresAt?.description ?? "indefinite")")
        return state
    }

    // Calculate expiration based on trigger
    var expiresAt: Date?
    var reason: ActiveBlock.BlockReason = .manualActivation

    if let trigger {
        switch trigger.type {
        case .timeBased:
            if let timeBased = trigger.timeBased {
                if let duration = timeBased.durationSeconds {
                    expiresAt = Date().addingTimeInterval(TimeInterval(duration))
                } else if let endTime = timeBased.endTime {
                    expiresAt = endTime
                }
            }
            reason = .timeBasedTrigger

        case .scheduleBased:
            // For schedule-based, expiration is calculated by TriggerEvaluator
            reason = .scheduleBasedTrigger

        case .visitCount:
            if let visitConfig = trigger.visitCount {
                expiresAt = Date().addingTimeInterval(TimeInterval(visitConfig.blockDurationSeconds))
            }
            reason = .visitCountTrigger
        }
    }

    // Create active block
    let block = ActiveBlock(
        blocklistId: blocklistId,
        domains: blocklist.domains,
        mode: blocklist.mode,
        expiresAt: expiresAt,
        reason: reason,
        isLocked: isLocked
    )

    // Remove any existing blocks for this blocklist
    mutableState.activeBlocks.removeAll { $0.blocklistId == blocklistId }

    // Add new block
    mutableState.activeBlocks.append(block)
    mutableState.blocklists[blocklistIdx].isActive = true
    mutableState.lastUpdated = Date()

    let modeLabel = blocklist.mode == .allow ? "allow list" : "blocklist"
    log.info("Activated \(modeLabel) '\(blocklist.name)' - locked: \(isLocked), expires: \(expiresAt?.description ?? "indefinite")")

    return mutableState
}

func deactivateBlocklist(_ blocklistId: UUID, state: WillpowerState) -> WillpowerState {
    var mutableState = state

    // Check if there's a locked block that hasn't expired
    if let block = mutableState.activeBlocks.first(where: { $0.blocklistId == blocklistId }),
       block.isLocked && !block.isExpired {
        log.warning("REJECTED: Cannot deactivate locked blocklist until \(block.expiresAt?.description ?? "indefinite")")
        log.info("This is the 'willpower' in Willpower - blocks cannot be bypassed!")
        return state  // REJECT the deactivation
    }

    // Remove active blocks for this blocklist
    mutableState.activeBlocks.removeAll { $0.blocklistId == blocklistId }

    // Mark blocklist as inactive
    if let idx = mutableState.blocklists.firstIndex(where: { $0.id == blocklistId }) {
        mutableState.blocklists[idx].isActive = false
        log.info("Deactivated blocklist '\(mutableState.blocklists[idx].name)'")
    }

    mutableState.lastUpdated = Date()
    return mutableState
}

// MARK: - Trigger Evaluation

func evaluateTriggers(
    state: WillpowerState,
    triggerEvaluator: TriggerEvaluator
) -> WillpowerState {
    var mutableState = state

    // PART 1: Evaluate independent triggers (new architecture)
    mutableState = evaluateIndependentTriggers(state: mutableState)

    // PART 2: Evaluate blocklist schedule triggers (legacy, still useful)
    for (idx, blocklist) in mutableState.blocklists.enumerated() {
        // Only handle schedule-based triggers here (visit-count now independent)
        let hasScheduleTrigger = blocklist.triggers.contains { $0.type == .scheduleBased && $0.isEnabled }
        guard hasScheduleTrigger else { continue }

        // Check if already has an active block
        if let existingBlock = mutableState.activeBlocks.first(where: { $0.blocklistId == blocklist.id }),
           !existingBlock.isExpired {
            continue  // Already blocked
        }

        // Check schedule-based triggers
        for trigger in blocklist.triggers where trigger.type == .scheduleBased && trigger.isEnabled {
            let result = triggerEvaluator.evaluateTrigger(trigger, visitRecords: mutableState.visitRecords)

            if case .active(let expiresAt) = result {
                // Schedule window is active
                let existingScheduleBlock = mutableState.activeBlocks.first {
                    $0.blocklistId == blocklist.id && $0.reason == .scheduleBasedTrigger
                }

                if existingScheduleBlock == nil {
                    log.info("Schedule window active for '\(blocklist.name)'")

                    let block = ActiveBlock(
                        blocklistId: blocklist.id,
                        domains: blocklist.domains,
                        mode: blocklist.mode,
                        expiresAt: expiresAt,
                        reason: .scheduleBasedTrigger,
                        isLocked: true  // Schedule blocks are locked (controlled by schedule)
                    )

                    mutableState.activeBlocks.append(block)
                    mutableState.blocklists[idx].isActive = true
                    mutableState.lastUpdated = Date()
                }

                break
            }
        }
    }

    return mutableState
}

/// Evaluate independent visit-count triggers
func evaluateIndependentTriggers(state: WillpowerState) -> WillpowerState {
    var mutableState = state

    for trigger in mutableState.independentTriggers where trigger.isEnabled {
        // Calculate total visits for this trigger's patterns
        var totalVisits = 0
        for pattern in trigger.urlPatterns {
            if let record = mutableState.visitRecords.first(where: { $0.patternId == pattern.id }) {
                totalVisits += record.visitCount
            }
        }

        // Check if threshold exceeded
        guard totalVisits >= trigger.maxVisits else { continue }

        // Process each pattern's block action
        for pattern in trigger.urlPatterns {
            // Check if this pattern already has an active block (uses pattern.id as block identifier)
            if mutableState.activeBlocks.contains(where: { $0.blocklistId == pattern.id && !$0.isExpired }) {
                continue  // Already blocked
            }

            let expiresAt = Date().addingTimeInterval(TimeInterval(trigger.blockDurationSeconds))

            switch pattern.blockAction {
            case .blockDomain:
                // Block just the pattern's associated domain
                log.info("Visit threshold exceeded - blocking domain '\(pattern.associatedDomain)'")

                let block = ActiveBlock(
                    blocklistId: pattern.id,  // Use pattern ID to track this specific block
                    domains: [pattern.associatedDomain],
                    expiresAt: expiresAt,
                    reason: .visitCountTrigger,
                    isLocked: true
                )

                mutableState.activeBlocks.append(block)
                mutableState.lastUpdated = Date()

            case .activateBlocklist(let blocklistId):
                // Activate the specified blocklist
                if let blocklist = mutableState.blocklists.first(where: { $0.id == blocklistId }) {
                    // Check if blocklist already has an active block
                    let existingBlocklistBlock = mutableState.activeBlocks.first {
                        $0.blocklistId == blocklistId && !$0.isExpired
                    }

                    if existingBlocklistBlock == nil {
                        log.info("Visit threshold exceeded - activating blocklist '\(blocklist.name)'")

                        let block = ActiveBlock(
                            blocklistId: blocklistId,
                            domains: blocklist.domains,
                            expiresAt: expiresAt,
                            reason: .visitCountTrigger,
                            isLocked: true
                        )

                        mutableState.activeBlocks.append(block)

                        // Mark blocklist as active
                        if let idx = mutableState.blocklists.firstIndex(where: { $0.id == blocklistId }) {
                            mutableState.blocklists[idx].isActive = true
                        }

                        mutableState.lastUpdated = Date()
                    }
                } else {
                    log.warning("Blocklist \(blocklistId) not found for trigger activation")
                }
            }
        }

        // Reset visit counts after triggering
        for pattern in trigger.urlPatterns {
            if let idx = mutableState.visitRecords.firstIndex(where: { $0.patternId == pattern.id }) {
                mutableState.visitRecords[idx].reset()
            }
        }
    }

    return mutableState
}

// MARK: - Expired Block Cleanup

func cleanupExpiredBlocks(state: WillpowerState) -> WillpowerState {
    var mutableState = state
    let expiredBlocks = mutableState.activeBlocks.filter { $0.isExpired }

    if !expiredBlocks.isEmpty {
        log.info("Cleaning up \(expiredBlocks.count) expired block(s)")

        for block in expiredBlocks {
            // Mark blocklist as inactive if no other active blocks
            if let idx = mutableState.blocklists.firstIndex(where: { $0.id == block.blocklistId }) {
                let hasOtherActiveBlock = mutableState.activeBlocks.contains {
                    $0.blocklistId == block.blocklistId && $0.id != block.id && !$0.isExpired
                }
                if !hasOtherActiveBlock {
                    mutableState.blocklists[idx].isActive = false
                }
            }
        }

        mutableState.activeBlocks.removeAll { $0.isExpired }
        mutableState.lastUpdated = Date()
    }

    return mutableState
}

// MARK: - Dual-Layer Blocking (Hosts + PF Firewall)

func applyBlocks(
    state: WillpowerState,
    hostsManager: HostsManager,
    packetFilterManager: PacketFilterManager
) throws {
    // Collect blocked domains (from .block mode active blocks)
    var blockedDomains = Set<String>()
    for block in state.activeBlocks where !block.isExpired && block.mode == .block {
        for domain in block.domains {
            blockedDomains.insert(domain.lowercased())
        }
    }

    // Collect allowed domains (from .allow mode active blocks)
    var allowedDomains = Set<String>()
    let isAllowListActive = state.hasActiveAllowList
    for block in state.activeBlocks where !block.isExpired && block.mode == .allow {
        for domain in block.domains {
            allowedDomains.insert(domain.lowercased())
        }
    }

    // Block wins: remove blocked domains from allowed set
    allowedDomains.subtract(blockedDomains)

    // Check if anything changed (nil = never synced, always sync on first run)
    if let prevBlocked = previousBlockedDomains,
       let prevAllowed = previousAllowedDomains,
       blockedDomains == prevBlocked && allowedDomains == prevAllowed {
        return  // No change, skip updates
    }

    log.info("Block state changed. Blocking \(blockedDomains.count) domain(s), allowing \(allowedDomains.count) domain(s), allowList=\(isAllowListActive)")

    // Track success of each layer so we can retry on next iteration if either fails
    var allLayersSucceeded = true

    // LAYER 1: Hosts file blocking (block-mode domains only — allow list handled by PF)
    do {
        try hostsManager.applyBlocklistAndFlush(domains: Array(blockedDomains))
        log.info("Layer 1: Hosts file updated")
    } catch HostsManager.HostsError.permissionDenied {
        log.error("Layer 1: Hosts file - permission denied (not running as root)")
        allLayersSucceeded = false
    } catch {
        log.error("Layer 1: Hosts file error - \(error)")
        allLayersSucceeded = false
    }

    // LAYER 2: PF firewall (unified rules for both block and allow modes)
    do {
        try packetFilterManager.applyRules(
            blockedDomains: Array(blockedDomains),
            allowedDomains: Array(allowedDomains),
            isAllowListActive: isAllowListActive
        )
        log.info("Layer 2: PF firewall rules applied")
    } catch PacketFilterManager.PFError.permissionDenied {
        log.error("Layer 2: PF firewall - permission denied (not running as root)")
        allLayersSucceeded = false
    } catch {
        log.error("Layer 2: PF firewall error - \(error)")
        allLayersSucceeded = false
    }

    // Only update tracking if both layers succeeded.
    // If either failed, leave tracking stale so the next iteration
    // re-enters this function and retries both layers.
    if allLayersSucceeded {
        previousBlockedDomains = blockedDomains
        previousAllowedDomains = allowedDomains
    }
}
