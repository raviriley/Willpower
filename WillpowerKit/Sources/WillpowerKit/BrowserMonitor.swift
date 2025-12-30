//
//  BrowserMonitor.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation
import AppKit

/// Monitors browser tabs for URL patterns using AppleScript
public actor BrowserMonitor {

    // MARK: - Types

    /// Supported browsers
    public enum Browser: String, CaseIterable, Sendable {
        case safari = "Safari"
        case chrome = "Google Chrome"
        case chromium = "Chromium"
        case brave = "Brave Browser"
        case arc = "Arc"
        case edge = "Microsoft Edge"
        case firefox = "Firefox"

        public var bundleIdentifier: String {
            switch self {
            case .safari: return "com.apple.Safari"
            case .chrome: return "com.google.Chrome"
            case .chromium: return "org.chromium.Chromium"
            case .brave: return "com.brave.Browser"
            case .arc: return "company.thebrowser.Browser"
            case .edge: return "com.microsoft.edgemac"
            case .firefox: return "org.mozilla.firefox"
            }
        }

        /// AppleScript to get the active tab URL
        public var urlAppleScript: String {
            switch self {
            case .safari:
                return """
                tell application "Safari"
                    if (count of windows) > 0 then
                        return URL of current tab of front window
                    end if
                end tell
                return ""
                """

            case .chrome, .chromium, .brave, .edge:
                // Chromium-based browsers share the same AppleScript model
                return """
                tell application "\(rawValue)"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                return ""
                """

            case .arc:
                // Arc has a slightly different model
                return """
                tell application "Arc"
                    if (count of windows) > 0 then
                        return URL of active tab of front window
                    end if
                end tell
                return ""
                """

            case .firefox:
                // Firefox doesn't support AppleScript well, but we can try
                return """
                tell application "Firefox"
                    if (count of windows) > 0 then
                        return URL of current tab of front window
                    end if
                end tell
                return ""
                """
            }
        }
    }

    /// Represents a browser tab snapshot
    public struct BrowserTab: Sendable {
        public let browser: Browser
        public let url: String
        public let timestamp: Date

        public init(browser: Browser, url: String, timestamp: Date = Date()) {
            self.browser = browser
            self.url = url
            self.timestamp = timestamp
        }
    }

    /// Monitoring errors
    public enum MonitorError: Error, LocalizedError {
        case scriptExecutionFailed(String)
        case browserNotRunning
        case accessibilityDenied

        public var errorDescription: String? {
            switch self {
            case .scriptExecutionFailed(let msg):
                return "AppleScript execution failed: \(msg)"
            case .browserNotRunning:
                return "Browser is not running"
            case .accessibilityDenied:
                return "Accessibility permissions not granted"
            }
        }
    }

    // MARK: - Properties

    private var isMonitoring = false
    private var monitoringTask: Task<Void, Never>?
    private var visitRecords: [UUID: VisitRecord] = [:]
    private var patterns: [URLPattern] = []
    private var pollingInterval: TimeInterval = 3.0

    /// Last seen URL to avoid counting the same page visit multiple times
    private var lastSeenURLs: [Browser: String] = [:]

    /// Minimum time between counting visits to the same URL (seconds)
    private var deduplicationInterval: TimeInterval = 30.0

    /// Last visit time per pattern for deduplication
    private var lastVisitTimes: [UUID: Date] = [:]

    /// Callback when a pattern match is detected
    public var onPatternMatch: (@Sendable (URLPattern, VisitRecord) async -> Void)?

    /// Callback when a threshold is exceeded
    public var onThresholdExceeded: (@Sendable (URLPattern, VisitRecord, Int) async -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - Configuration

    /// Configure URL patterns to monitor
    public func setPatterns(_ patterns: [URLPattern]) {
        self.patterns = patterns

        // Initialize visit records for new patterns
        for pattern in patterns {
            if visitRecords[pattern.id] == nil {
                visitRecords[pattern.id] = VisitRecord(
                    patternId: pattern.id,
                    pattern: pattern.pattern,
                    visitCount: 0
                )
            }
        }

        // Remove records for patterns no longer being tracked
        let patternIds = Set(patterns.map { $0.id })
        visitRecords = visitRecords.filter { patternIds.contains($0.key) }
    }

    /// Set the polling interval in seconds
    public func setPollingInterval(_ interval: TimeInterval) {
        self.pollingInterval = max(1.0, interval)  // Minimum 1 second
    }

    /// Set the deduplication interval (minimum time between counting same URL)
    public func setDeduplicationInterval(_ interval: TimeInterval) {
        self.deduplicationInterval = max(0, interval)
    }

    // MARK: - State Management

    /// Get current visit records
    public func getVisitRecords() -> [VisitRecord] {
        return Array(visitRecords.values)
    }

    /// Get visit record for a specific pattern
    public func getVisitRecord(for patternId: UUID) -> VisitRecord? {
        return visitRecords[patternId]
    }

    /// Restore visit records from saved state
    public func restoreVisitRecords(_ records: [VisitRecord]) {
        for record in records {
            visitRecords[record.patternId] = record
        }
    }

    /// Reset visit counts
    public func resetVisitCounts(patternIds: [UUID]? = nil) {
        if let patternIds {
            for id in patternIds {
                if var record = visitRecords[id] {
                    record.reset()
                    visitRecords[id] = record
                }
                lastVisitTimes[id] = nil
            }
        } else {
            for (id, var record) in visitRecords {
                record.reset()
                visitRecords[id] = record
            }
            lastVisitTimes.removeAll()
        }
    }

    // MARK: - Monitoring Control

    /// Start monitoring browsers
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollBrowsers()

                let interval = await self?.pollingInterval ?? 3.0
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }

        print("[BrowserMonitor] Started monitoring with \(pollingInterval)s interval")
    }

    /// Stop monitoring
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
        print("[BrowserMonitor] Stopped monitoring")
    }

    /// Check if monitoring is active
    public func isActive() -> Bool {
        return isMonitoring
    }

    // MARK: - Browser Interaction

    /// Get active tab from a specific browser (one-shot)
    public nonisolated func getActiveTab(browser: Browser) async -> BrowserTab? {
        guard isAppRunning(browser) else { return nil }

        guard let url = executeAppleScript(browser.urlAppleScript),
              !url.isEmpty else {
            return nil
        }

        return BrowserTab(browser: browser, url: url)
    }

    /// Get active tabs from all running browsers (one-shot)
    public nonisolated func getAllActiveTabs() async -> [BrowserTab] {
        var tabs: [BrowserTab] = []

        for browser in Browser.allCases {
            if let tab = await getActiveTab(browser: browser) {
                tabs.append(tab)
            }
        }

        return tabs
    }

    // MARK: - Private Polling

    private func pollBrowsers() async {
        for browser in Browser.allCases {
            guard isAppRunning(browser) else { continue }

            if let tab = await getActiveTab(browser: browser) {
                await checkPatternMatches(for: tab)
            }
        }
    }

    private func checkPatternMatches(for tab: BrowserTab) async {
        let now = Date()

        for pattern in patterns {
            guard pattern.matches(url: tab.url) else { continue }

            // Check deduplication - don't count same URL visit too frequently
            if let lastVisit = lastVisitTimes[pattern.id],
               now.timeIntervalSince(lastVisit) < deduplicationInterval {
                continue
            }

            // Also check if URL changed for this browser
            if lastSeenURLs[tab.browser] == tab.url {
                // Same URL as last poll, don't count
                continue
            }

            // Record the visit
            await recordVisit(for: pattern, url: tab.url, browser: tab.browser)
        }

        // Update last seen URL for this browser
        lastSeenURLs[tab.browser] = tab.url
    }

    private func recordVisit(for pattern: URLPattern, url: String, browser: Browser) async {
        var record = visitRecords[pattern.id] ?? VisitRecord(
            patternId: pattern.id,
            pattern: pattern.pattern
        )

        record.recordVisit()
        visitRecords[pattern.id] = record
        lastVisitTimes[pattern.id] = Date()

        print("[BrowserMonitor] Visit recorded: \(pattern.pattern) - count: \(record.visitCount)")

        // Notify callback
        await onPatternMatch?(pattern, record)
    }

    // MARK: - AppleScript Execution

    private nonisolated func isAppRunning(_ browser: Browser) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == browser.bundleIdentifier
        }
    }

    private nonisolated func executeAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }

        let result = appleScript.executeAndReturnError(&error)

        if let error {
            // Don't log errors for browsers that aren't scriptable or not running
            let errorNumber = error["NSAppleScriptErrorNumber"] as? Int ?? 0
            if errorNumber != -600 && errorNumber != -1708 {  // Not running / not scriptable
                print("[BrowserMonitor] AppleScript error: \(error)")
            }
            return nil
        }

        return result.stringValue
    }
}

// MARK: - Accessibility Helper

/// Helper for checking and requesting accessibility permissions
public struct AccessibilityHelper: Sendable {

    // The string value of kAXTrustedCheckOptionPrompt
    // Using the literal string to avoid Swift 6 concurrency issues with the C global
    private static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"

    /// Check if accessibility permissions are granted
    /// Note: AppleScript automation permissions are different from Accessibility
    @MainActor
    public static func checkAccessibilityPermissions() -> Bool {
        let options = [trustedCheckOptionPrompt: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Prompt user for accessibility permissions
    @MainActor
    public static func requestAccessibilityPermissions() {
        let options = [trustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Preferences to Accessibility pane
    @MainActor
    public static func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Preferences to Automation pane
    @MainActor
    public static func openAutomationPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
