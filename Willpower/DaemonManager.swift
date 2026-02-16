//
//  DaemonManager.swift
//  Willpower
//
//  Manages registration and status of the privileged WillpowerDaemon
//  using SMAppService.daemon (macOS 13+)
//

import Foundation
import ServiceManagement
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

    // MARK: - Computed Properties

    /// True if daemon is registered but user hasn't enabled it in System Settings
    var needsApproval: Bool {
        status == .requiresApproval
    }

    /// True if daemon is fully enabled and running
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
            return "Running"
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

        // Clear any previous error if daemon is now successfully running
        if status == .enabled {
            lastError = nil
        }
    }

    /// Register the daemon with launchd
    /// After registration, user must enable in System Settings
    func register() {
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
        lastError = nil
        logger.info("Updating daemon (unregister + re-register)...")

        let service = SMAppService.daemon(plistName: Self.plistName)

        // Unregister first
        do {
            try service.unregister()
            logger.info("Daemon unregistered for update")
        } catch {
            logger.warning("Unregister during update failed (may not be registered): \(error.localizedDescription)")
        }

        // Small delay to let launchd clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            do {
                try service.register()
                logger.info("Daemon re-registered successfully")
                refreshStatus()
            } catch {
                logger.error("Daemon re-registration failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
                refreshStatus()
            }
        }
    }

    /// Unregister the daemon from launchd
    func unregister() {
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
