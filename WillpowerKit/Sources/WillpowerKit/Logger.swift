//
//  Logger.swift
//  WillpowerKit
//
//  Provides unified logging using os_log for all Willpower components.
//

import Foundation
import os.log

/// Unified logging for Willpower components
/// Uses os_log with appropriate subsystems and categories
public enum WillpowerLogger {

    // MARK: - Subsystems

    /// Subsystem for the main app
    public static let appSubsystem = "com.raviriley.Willpower"

    /// Subsystem for the daemon
    public static let daemonSubsystem = "com.raviriley.WillpowerDaemon"

    /// Subsystem for the shared kit
    public static let kitSubsystem = "com.raviriley.WillpowerKit"

    // MARK: - Categories

    public enum Category: String {
        case general = "General"
        case ipc = "IPC"
        case hosts = "Hosts"
        case packetFilter = "PacketFilter"
        case browser = "BrowserMonitor"
        case triggers = "Triggers"
        case viewModel = "ViewModel"
        case daemon = "Daemon"
        case settings = "Settings"
    }

    // MARK: - Logger Cache

    private static var loggers: [String: Logger] = [:]
    private static let lock = NSLock()

    /// Get or create a logger for the given subsystem and category
    public static func logger(subsystem: String, category: Category) -> Logger {
        let key = "\(subsystem).\(category.rawValue)"

        lock.lock()
        defer { lock.unlock() }

        if let existing = loggers[key] {
            return existing
        }

        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[key] = logger
        return logger
    }

    // MARK: - Convenience Loggers

    /// Logger for WillpowerKit IPC operations
    public static var ipc: Logger {
        logger(subsystem: kitSubsystem, category: .ipc)
    }

    /// Logger for WillpowerKit hosts file operations
    public static var hosts: Logger {
        logger(subsystem: kitSubsystem, category: .hosts)
    }

    /// Logger for WillpowerKit packet filter operations
    public static var packetFilter: Logger {
        logger(subsystem: kitSubsystem, category: .packetFilter)
    }

    /// Logger for WillpowerKit browser monitoring
    public static var browser: Logger {
        logger(subsystem: kitSubsystem, category: .browser)
    }

    /// Logger for daemon operations
    public static var daemon: Logger {
        logger(subsystem: daemonSubsystem, category: .daemon)
    }

    /// Logger for app ViewModel operations
    public static var viewModel: Logger {
        logger(subsystem: appSubsystem, category: .viewModel)
    }

    /// Logger for app Settings operations
    public static var settings: Logger {
        logger(subsystem: appSubsystem, category: .settings)
    }
}

// MARK: - Daemon Stdout Logger

/// Special logger for daemon that flushes stdout (needed for launchd logging)
/// This wraps os_log but also outputs to stdout for launchd capture
public struct DaemonLogger {
    private let osLogger: Logger
    private let prefix: String

    public init(category: WillpowerLogger.Category = .daemon) {
        self.osLogger = WillpowerLogger.logger(
            subsystem: WillpowerLogger.daemonSubsystem,
            category: category
        )
        self.prefix = "[WillpowerDaemon]"
    }

    /// Log at info level (also prints to stdout for launchd)
    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        // Also print to stdout and flush for launchd capture
        print("\(prefix) \(message)")
        fflush(stdout)
    }

    /// Log at debug level
    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }

    /// Log at warning level (also prints to stdout)
    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        print("\(prefix) WARNING: \(message)")
        fflush(stdout)
    }

    /// Log at error level (also prints to stdout)
    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        print("\(prefix) ERROR: \(message)")
        fflush(stdout)
    }

    /// Log at fault level (critical errors, also prints to stdout)
    public func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        print("\(prefix) FATAL: \(message)")
        fflush(stdout)
    }
}
