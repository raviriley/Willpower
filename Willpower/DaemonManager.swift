//
//  DaemonManager.swift
//  Willpower
//
//  Manages registration and status of the privileged WillpowerDaemon
//  using SMAppService.daemon (macOS 13+)
//

import Foundation
import ServiceManagement
import WillpowerKit
import AppKit
import os.log

private let logger = Logger(subsystem: "raviriley.Willpower", category: "DaemonManager")

@MainActor @Observable
final class DaemonManager {

    // MARK: - Constants

    /// The launchd plist filename (must include .plist extension)
    static let plistName = "raviriley.WillpowerDaemon.plist"

    // MARK: - Published State

    /// Current daemon registration status
    private(set) var status: SMAppService.Status = .notRegistered

    /// Last error message if registration failed
    private(set) var lastError: String?

    /// True while a reinstall operation is in progress
    private(set) var isReinstalling: Bool = false

    // MARK: - Computed Properties

    /// True if daemon is registered but user hasn't enabled it in System Settings
    var needsApproval: Bool {
        status == .requiresApproval
    }

    /// True if the daemon is registered and approved (heartbeat confirms liveness)
    var isEnabled: Bool {
        status == .enabled
    }

    /// True if daemon needs to be registered
    var needsInstallation: Bool {
        status == .notRegistered || status == .notFound
    }

    /// Human-readable status description
    var statusDescription: String {
        switch status {
        case .notRegistered:
            return "Not Installed"
        case .enabled:
            return "Registered"
        case .requiresApproval:
            return "Needs Approval"
        case .notFound:
            return "Not Found"
        @unknown default:
            return "Unknown"
        }
    }

    // MARK: - Initialization

    init() {
        logger.info("DaemonManager initializing with plist: \(Self.plistName)")
        logBundleInfo()
        refreshStatus()
    }

    // MARK: - Debug Helpers

    private func logBundleInfo() {
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            logger.error("Could not get bundle path")
            return
        }

        logger.info("App bundle path: \(bundlePath)")

        // Check for daemon binary
        let daemonPath = "\(bundlePath)/Contents/MacOS/WillpowerDaemon"
        let daemonExists = FileManager.default.fileExists(atPath: daemonPath)
        logger.info("Daemon binary exists at \(daemonPath): \(daemonExists)")

        // Check for launchd plist
        let plistPath = "\(bundlePath)/Contents/Library/LaunchDaemons/\(Self.plistName)"
        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        logger.info("Launchd plist exists at \(plistPath): \(plistExists)")

        if plistExists {
            // Try to read plist content
            if let plistData = FileManager.default.contents(atPath: plistPath),
               let plistString = String(data: plistData, encoding: .utf8) {
                logger.debug("Plist content:\n\(plistString)")
            }
        }
    }

    // MARK: - Public Methods

    /// Refresh the daemon status from SMAppService
    func refreshStatus() {
        let service = SMAppService.daemon(plistName: Self.plistName)
        status = service.status
        logger.info("Daemon status: \(self.statusDescription) (raw: \(String(describing: self.status)))")
    }

    /// Register the daemon with launchd
    /// After registration, user must enable in System Settings
    func register() {
        guard !isReinstalling else { return }
        lastError = nil
        logger.info("Attempting to register daemon...")

        let service = SMAppService.daemon(plistName: Self.plistName)

        do {
            try service.register()
            logger.info("Daemon registration succeeded")
            refreshStatus()
        } catch let error as NSError {
            logger.error("Daemon registration failed: \(error.localizedDescription)")
            logger.error("Error domain: \(error.domain), code: \(error.code)")
            logger.error("Error userInfo: \(error.userInfo)")

            // Provide more specific error messages
            if error.domain == "SMAppServiceErrorDomain" {
                switch error.code {
                case 1:
                    lastError = "Invalid plist or daemon not found in bundle"
                case 2:
                    lastError = "Authorization denied"
                case 3:
                    lastError = "Daemon already registered"
                default:
                    lastError = "\(error.localizedDescription) (code: \(error.code))"
                }
            } else {
                lastError = error.localizedDescription
            }

            refreshStatus()
        }
    }

    /// Unregister and re-register the daemon to pick up a new binary
    func update() {
        reinstall()
    }

    /// Unregister and re-register the daemon. Handles the case where the daemon
    /// is already registered but not running (the common "stuck" state).
    func reinstall() {
        guard !isReinstalling else { return }
        lastError = nil
        isReinstalling = true
        lastRecoveryAttempt = Date()
        logger.info("Reinstalling daemon (unregister + re-register)...")

        Task { @MainActor in
            defer {
                isReinstalling = false
                refreshStatus()
            }
            let service = SMAppService.daemon(plistName: Self.plistName)
            do {
                // Wait for launchd to finish removing the old job before registering.
                if service.status != .notRegistered && service.status != .notFound {
                    try await service.unregister()
                }
                var registrationError: Error?
                for attempt in 0..<4 {
                    do {
                        try service.register()
                        registrationError = nil
                        break
                    } catch {
                        registrationError = error
                        if attempt < 3 {
                            try await Task.sleep(for: .seconds(attempt + 1))
                        }
                    }
                }
                if let registrationError { throw registrationError }
                refreshStatus()
                if needsApproval {
                    lastError = "Enable Willpower in System Settings > General > Login Items, then refresh status."
                    openSystemSettings()
                    return
                }

                // Registration alone does not prove that the new daemon started.
                let ipc = IPCManager()
                let previousHeartbeat = ipc.lastDaemonHeartbeat()
                for _ in 0..<30 {
                    try await Task.sleep(for: .seconds(1))
                    if ipc.isDaemonAlive(), let heartbeat = ipc.lastDaemonHeartbeat(),
                       heartbeat > (previousHeartbeat ?? .distantPast) {
                        lastError = nil
                        return
                    }
                }
                lastError = "The daemon is registered but did not respond within 30 seconds. Check that Willpower is allowed in System Settings > General > Login Items."
            } catch {
                logger.error("Daemon reinstall failed: \(error.localizedDescription)")
                refreshStatus()
                if needsApproval {
                    lastError = "Enable Willpower in System Settings > General > Login Items, then refresh status."
                    openSystemSettings()
                } else {
                    lastError = error.localizedDescription
                }
            }
        }
    }

    /// Give launchd time to restart after a crash or wake before attempting repair.
    private var offlineSince: Date?
    private var lastRecoveryAttempt: Date?

    func checkHealth(isAlive: Bool) {
        if isAlive {
            offlineSince = nil
            return
        }
        let now = Date()
        guard let offlineSince else {
            self.offlineSince = now
            return
        }
        guard now.timeIntervalSince(offlineSince) >= 60,
              !isReinstalling,
              lastRecoveryAttempt.map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return }
        refreshStatus()
        // Never automatically register a service that the user disabled or removed.
        guard status == .enabled else { return }
        lastRecoveryAttempt = now
        reinstall()
    }

    /// Unregister the daemon from launchd
    func unregister() {
        guard !isReinstalling else { return }
        lastError = nil
        logger.info("Attempting to unregister daemon...")

        do {
            try SMAppService.daemon(plistName: Self.plistName).unregister()
            logger.info("Daemon unregistration succeeded")
            refreshStatus()
        } catch let error as NSError {
            logger.error("Daemon unregistration failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            refreshStatus()
        }
    }

    /// Open System Settings to Login Items where user can approve the daemon
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
