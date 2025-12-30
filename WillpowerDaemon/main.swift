import Foundation
import WillpowerKit

// MARK: - Configuration

private let daemonVersion = "1.0.0"
private let runLoopInterval: TimeInterval = 5.0
private let browserPollingInterval: TimeInterval = 3.0
private let heartbeatInterval: TimeInterval = 5.0

// MARK: - Main Entry Point

print("[WillpowerDaemon] Starting v\(daemonVersion)...")
print("[WillpowerDaemon] PID: \(getpid()), UID: \(getuid())")

// Check if running as root (required for /etc/hosts modification)
if getuid() != 0 {
    print("[WillpowerDaemon] WARNING: Not running as root (UID: \(getuid()))")
    print("[WillpowerDaemon] /etc/hosts modification will fail without root privileges")
    print("[WillpowerDaemon] Run with sudo or install as LaunchDaemon")
}

// Initialize components
let hostsManager = HostsManager()
let ipcManager = IPCManager()
let browserMonitor = BrowserMonitor()
let triggerEvaluator = TriggerEvaluator()

// Check IPC availability
guard ipcManager.isAvailable else {
    print("[WillpowerDaemon] FATAL: App Groups not available")
    print("[WillpowerDaemon] Ensure entitlements are configured correctly")
    exit(1)
}

// Load initial state or create default
var state = ipcManager.loadStateOrDefault()
state.daemonVersion = daemonVersion
print("[WillpowerDaemon] Loaded state: \(state.blocklists.count) blocklists, \(state.activeBlocks.count) active blocks")

// Start async operations
Task {
    // Configure browser monitor
    await configureBrowserMonitor(browserMonitor, state: state)
    await browserMonitor.startMonitoring()

    print("[WillpowerDaemon] Initialized. Entering run loop...")

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

            // Process pending commands from app
            state = try await processCommands(
                ipcManager: ipcManager,
                state: state,
                browserMonitor: browserMonitor
            )

            // Update visit records from browser monitor
            let currentRecords = await browserMonitor.getVisitRecords()
            state = updateVisitRecords(state: state, newRecords: currentRecords)

            // Evaluate triggers and update blocks
            state = evaluateTriggers(
                state: state,
                triggerEvaluator: triggerEvaluator
            )

            // Clean up expired blocks
            state = cleanupExpiredBlocks(state: state)

            // Apply hosts file changes
            try applyHostsBlocks(state: state, hostsManager: hostsManager)

            // Save state
            try ipcManager.saveState(state)

        } catch {
            print("[WillpowerDaemon] Error in run loop: \(error)")
        }

        // Sleep until next iteration
        try? await Task.sleep(nanoseconds: UInt64(runLoopInterval * 1_000_000_000))
    }
}

// Keep the process alive
dispatchMain()

// MARK: - Browser Monitor Configuration

func configureBrowserMonitor(_ monitor: BrowserMonitor, state: WillpowerState) async {
    // Collect all URL patterns from visit-count triggers
    var patterns: [URLPattern] = []

    for blocklist in state.blocklists {
        for trigger in blocklist.triggers where trigger.type == .visitCount {
            if let visitConfig = trigger.visitCount {
                patterns.append(contentsOf: visitConfig.urlPatterns)
            }
        }
    }

    await monitor.setPatterns(patterns)
    await monitor.setPollingInterval(browserPollingInterval)
    await monitor.restoreVisitRecords(state.visitRecords)
}

// MARK: - Command Processing

func processCommands(
    ipcManager: IPCManager,
    state: WillpowerState,
    browserMonitor: BrowserMonitor
) async throws -> WillpowerState {
    var mutableState = state
    let commands = try ipcManager.loadPendingCommands()

    guard !commands.isEmpty else { return state }

    print("[WillpowerDaemon] Processing \(commands.count) command(s)")

    for wrapper in commands {
        print("[WillpowerDaemon] Command: \(wrapper.command)")

        switch wrapper.command {
        case .activateBlocklist(let blocklistId, let trigger, let isLocked):
            mutableState = activateBlocklist(
                blocklistId,
                trigger: trigger,
                isLocked: isLocked,
                state: mutableState
            )

        case .deactivateBlocklist(let blocklistId):
            mutableState = deactivateBlocklist(blocklistId, state: mutableState)

        case .updateBlocklists(let blocklists):
            mutableState.blocklists = blocklists
            mutableState.lastUpdated = Date()
            // Reconfigure browser monitor with new patterns
            await configureBrowserMonitor(browserMonitor, state: mutableState)

        case .forceSync:
            mutableState.lastUpdated = Date()

        case .resetVisitCounts(let patternIds):
            await browserMonitor.resetVisitCounts(patternIds: patternIds)
            // Also reset in state
            if let ids = patternIds {
                for id in ids {
                    if let idx = mutableState.visitRecords.firstIndex(where: { $0.patternId == id }) {
                        mutableState.visitRecords[idx].reset()
                    }
                }
            } else {
                for idx in mutableState.visitRecords.indices {
                    mutableState.visitRecords[idx].reset()
                }
            }
        }

        try ipcManager.markCommandProcessed(wrapper.id)
    }

    return mutableState
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
        print("[WillpowerDaemon] Blocklist not found: \(blocklistId)")
        return state
    }

    let blocklist = mutableState.blocklists[blocklistIdx]

    // Check if already has an active locked block
    if let existingBlock = mutableState.activeBlocks.first(where: { $0.blocklistId == blocklistId }),
       existingBlock.isLocked && !existingBlock.isExpired {
        print("[WillpowerDaemon] Blocklist already has active locked block until \(existingBlock.expiresAt?.description ?? "indefinite")")
        return state
    }

    // Calculate expiration based on trigger
    var expiresAt: Date? = nil
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

    print("[WillpowerDaemon] Activated blocklist '\(blocklist.name)' - locked: \(isLocked), expires: \(expiresAt?.description ?? "indefinite")")

    return mutableState
}

func deactivateBlocklist(_ blocklistId: UUID, state: WillpowerState) -> WillpowerState {
    var mutableState = state

    // Check if there's a locked block that hasn't expired
    if let block = mutableState.activeBlocks.first(where: { $0.blocklistId == blocklistId }),
       block.isLocked && !block.isExpired {
        print("[WillpowerDaemon] REJECTED: Cannot deactivate locked blocklist until \(block.expiresAt?.description ?? "indefinite")")
        print("[WillpowerDaemon] This is the 'willpower' in Willpower - blocks cannot be bypassed!")
        return state  // REJECT the deactivation
    }

    // Remove active blocks for this blocklist
    mutableState.activeBlocks.removeAll { $0.blocklistId == blocklistId }

    // Mark blocklist as inactive
    if let idx = mutableState.blocklists.firstIndex(where: { $0.id == blocklistId }) {
        mutableState.blocklists[idx].isActive = false
        print("[WillpowerDaemon] Deactivated blocklist '\(mutableState.blocklists[idx].name)'")
    }

    mutableState.lastUpdated = Date()
    return mutableState
}

// MARK: - Visit Records Update

func updateVisitRecords(state: WillpowerState, newRecords: [VisitRecord]) -> WillpowerState {
    var mutableState = state

    for record in newRecords {
        if let idx = mutableState.visitRecords.firstIndex(where: { $0.patternId == record.patternId }) {
            mutableState.visitRecords[idx] = record
        } else {
            mutableState.visitRecords.append(record)
        }
    }

    return mutableState
}

// MARK: - Trigger Evaluation

func evaluateTriggers(
    state: WillpowerState,
    triggerEvaluator: TriggerEvaluator
) -> WillpowerState {
    var mutableState = state

    for (idx, blocklist) in mutableState.blocklists.enumerated() {
        // Skip if blocklist has no visit-count triggers
        let hasVisitTrigger = blocklist.triggers.contains { $0.type == .visitCount && $0.isEnabled }
        guard hasVisitTrigger else { continue }

        // Check if already has an active block
        let existingBlock = mutableState.activeBlocks.first { $0.blocklistId == blocklist.id }
        if existingBlock != nil && !existingBlock!.isExpired {
            continue  // Already blocked
        }

        // Evaluate visit-count triggers
        for trigger in blocklist.triggers where trigger.type == .visitCount && trigger.isEnabled {
            let result = triggerEvaluator.evaluateTrigger(trigger, visitRecords: mutableState.visitRecords)

            if case .active(let expiresAt) = result {
                // Threshold exceeded - activate block
                print("[WillpowerDaemon] Visit threshold exceeded for '\(blocklist.name)' - activating block")

                let block = ActiveBlock(
                    blocklistId: blocklist.id,
                    domains: blocklist.domains,
                    expiresAt: expiresAt,
                    reason: .visitCountTrigger,
                    isLocked: true  // Visit-triggered blocks are always locked
                )

                mutableState.activeBlocks.removeAll { $0.blocklistId == blocklist.id }
                mutableState.activeBlocks.append(block)
                mutableState.blocklists[idx].isActive = true
                mutableState.lastUpdated = Date()

                break  // Only need one active block per blocklist
            }
        }

        // Also check schedule-based triggers
        for trigger in blocklist.triggers where trigger.type == .scheduleBased && trigger.isEnabled {
            let result = triggerEvaluator.evaluateTrigger(trigger, visitRecords: mutableState.visitRecords)

            if case .active(let expiresAt) = result {
                // Schedule window is active
                let existingScheduleBlock = mutableState.activeBlocks.first {
                    $0.blocklistId == blocklist.id && $0.reason == .scheduleBasedTrigger
                }

                if existingScheduleBlock == nil {
                    print("[WillpowerDaemon] Schedule window active for '\(blocklist.name)'")

                    let block = ActiveBlock(
                        blocklistId: blocklist.id,
                        domains: blocklist.domains,
                        expiresAt: expiresAt,
                        reason: .scheduleBasedTrigger,
                        isLocked: false  // Schedule blocks are unlocked (natural expiry)
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

// MARK: - Expired Block Cleanup

func cleanupExpiredBlocks(state: WillpowerState) -> WillpowerState {
    var mutableState = state
    let expiredBlocks = mutableState.activeBlocks.filter { $0.isExpired }

    if !expiredBlocks.isEmpty {
        print("[WillpowerDaemon] Cleaning up \(expiredBlocks.count) expired block(s)")

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

// MARK: - Hosts File Application

func applyHostsBlocks(state: WillpowerState, hostsManager: HostsManager) throws {
    // Collect all domains from active non-expired blocks
    var allDomains = Set<String>()

    for block in state.activeBlocks where !block.isExpired {
        for domain in block.domains {
            allDomains.insert(domain.lowercased())
        }
    }

    // Get currently blocked domains
    let currentDomains: Set<String>
    do {
        currentDomains = Set(try hostsManager.readManagedDomains().map { $0.lowercased() })
    } catch HostsManager.HostsError.permissionDenied {
        print("[WillpowerDaemon] Cannot read hosts file - permission denied (not running as root)")
        return
    }

    // Normalize current domains (remove www. prefixes for comparison)
    let normalizedCurrent = Set(currentDomains.map { domain -> String in
        domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
    })

    // Only update if there's a change
    if allDomains != normalizedCurrent {
        print("[WillpowerDaemon] Updating hosts file. Blocking \(allDomains.count) domain(s)")

        do {
            try hostsManager.applyBlocklistAndFlush(domains: Array(allDomains))
            print("[WillpowerDaemon] Hosts file updated and DNS cache flushed")
        } catch HostsManager.HostsError.permissionDenied {
            print("[WillpowerDaemon] ERROR: Cannot write hosts file - permission denied")
            print("[WillpowerDaemon] Daemon must run as root to modify /etc/hosts")
        }
    }
}
