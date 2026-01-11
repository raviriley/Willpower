//
//  AppDelegate.swift
//  Willpower
//
//  Created by Claude on 1/5/26.
//

import AppKit
import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "raviriley.Willpower", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var viewModel: WillpowerViewModel?
    private var mainWindow: NSWindow?
    private var isWindowVisible = false
    private var iconUpdateTimer: Timer?
    private lazy var logoIcon: NSImage = createLogoIcon()

    // MARK: - Configuration

    func configure(with viewModel: WillpowerViewModel) {
        self.viewModel = viewModel

        // Ensure menu bar is set up (may not have happened in applicationDidFinishLaunching with @NSApplicationDelegateAdaptor)
        if statusItem == nil {
            setupMenuBarItem()
            startIconUpdateTimer()
            logger.info("Menu bar item created in configure()")
        }

        // Start state sync (idempotent - safe to call multiple times)
        viewModel.startStateSync()

        // Update icon immediately with current state
        updateMenuBarIcon()
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarItem()

        // Start state sync immediately (not dependent on window)
        // This ensures browser monitoring runs even if window isn't shown
        viewModel?.startStateSync()

        // Check if launched at login vs user-initiated
        let launchedAtLogin = isLaunchedAtLogin()

        if launchedAtLogin {
            // Hide dock icon, don't show window - run as menu bar only
            NSApp.setActivationPolicy(.accessory)
            isWindowVisible = false
            logger.info("Launched at login - running in background")
        } else {
            // Normal launch - window will be shown by SwiftUI WindowGroup
            NSApp.setActivationPolicy(.regular)
            isWindowVisible = true
            logger.info("User-initiated launch - showing window")
        }

        // Start timer to update icon periodically
        startIconUpdateTimer()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Always allow termination - warnings are handled by quitCompletely()
        // This is called when:
        // 1. User uses "Quit Completely" (warning already shown if needed)
        // 2. System requests termination (logout, shutdown - should allow)
        // 3. External force quit (should allow)
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.stopStateSync()
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When user clicks dock icon or opens app again, show the window
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - Launch Detection

    private func isLaunchedAtLogin() -> Bool {
        // Method 1: Check for AppleEvent login item launch
        if let event = NSAppleEventManager.shared().currentAppleEvent {
            // Check if launched by login item mechanism
            if let propData = event.paramDescriptor(forKeyword: keyAEPropData)?.stringValue,
               propData.contains("com.apple.loginitemregistration") {
                return true
            }
        }

        // Method 2: Check if we're launching very close to boot time
        // This helps catch login launches that don't set the AppleEvent properly
        let bootTime = ProcessInfo.processInfo.systemUptime
        if bootTime < 120 { // Within 2 minutes of boot
            // Check if Launch at Login is enabled
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }

        return false
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBarItem() {
        // Prevent duplicate status items
        guard statusItem == nil else { return }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        logger.debug("Created NSStatusItem")

        if let button = statusItem?.button {
            updateMenuBarIcon()
            button.action = #selector(menuBarButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            logger.debug("Configured status item button")
        } else {
            logger.error("Failed to get status item button")
        }

        setupMenu()
    }

    private func setupMenu() {
        statusMenu = NSMenu()

        let openItem = NSMenuItem(title: "Open Willpower", action: #selector(showMainWindow), keyEquivalent: "")
        openItem.target = self
        statusMenu?.addItem(openItem)

        statusMenu?.addItem(NSMenuItem.separator())

        // Status info (non-clickable)
        let statusItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusItem.tag = 100 // Tag for updating
        statusMenu?.addItem(statusItem)

        statusMenu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Completely", action: #selector(quitCompletelyFromMenu), keyEquivalent: "")
        quitItem.target = self
        statusMenu?.addItem(quitItem)
    }

    private func startIconUpdateTimer() {
        // Prevent duplicate timers
        guard iconUpdateTimer == nil else { return }

        iconUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.updateMenuBarIcon()
                self?.updateStatusMenuItem()
            }
        }
    }

    func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let isBlocking = !(viewModel?.activeBlocks.isEmpty ?? true)

        if isBlocking {
            // Active state: filled shield SF Symbol
            if let image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "Willpower Active") {
                let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                button.image = image.withSymbolConfiguration(config)
            }
        } else {
            // Inactive state: custom logo (shield with W)
            button.image = logoIcon
        }
    }

    /// Creates the custom Willpower logo icon for menu bar (shield with W)
    private func createLogoIcon() -> NSImage {
        let size: CGFloat = 18  // Menu bar icon size
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.setStroke()

            // Scale factor: SVG viewBox is 24x24, we want 18x18
            let scale = size / 24.0
            let lineWidth: CGFloat = 1.5

            // Draw shield outline (based on logo.svg path)
            let shieldPath = NSBezierPath()
            shieldPath.lineWidth = lineWidth
            shieldPath.lineCapStyle = .round
            shieldPath.lineJoinStyle = .round

            // Shield path - approximate the Lucide shield shape
            // Start from bottom-left curve up
            shieldPath.move(to: NSPoint(x: 4 * scale, y: (24 - 13) * scale))
            shieldPath.line(to: NSPoint(x: 4 * scale, y: (24 - 6) * scale))

            // Top left corner and top curve
            shieldPath.curve(to: NSPoint(x: 12 * scale, y: (24 - 2.28) * scale),
                            controlPoint1: NSPoint(x: 4 * scale, y: (24 - 5) * scale),
                            controlPoint2: NSPoint(x: 9 * scale, y: (24 - 2.28) * scale))

            // Top right curve
            shieldPath.curve(to: NSPoint(x: 20 * scale, y: (24 - 6) * scale),
                            controlPoint1: NSPoint(x: 15 * scale, y: (24 - 2.28) * scale),
                            controlPoint2: NSPoint(x: 20 * scale, y: (24 - 5) * scale))

            // Right side down
            shieldPath.line(to: NSPoint(x: 20 * scale, y: (24 - 13) * scale))

            // Bottom right curve to center
            shieldPath.curve(to: NSPoint(x: 12 * scale, y: (24 - 21.95) * scale),
                            controlPoint1: NSPoint(x: 20 * scale, y: (24 - 18) * scale),
                            controlPoint2: NSPoint(x: 16 * scale, y: (24 - 21) * scale))

            // Bottom left curve back to start
            shieldPath.curve(to: NSPoint(x: 4 * scale, y: (24 - 13) * scale),
                            controlPoint1: NSPoint(x: 8 * scale, y: (24 - 21) * scale),
                            controlPoint2: NSPoint(x: 4 * scale, y: (24 - 18) * scale))

            shieldPath.stroke()

            // Draw W inside the shield
            let wPath = NSBezierPath()
            wPath.lineWidth = lineWidth
            wPath.lineCapStyle = .round
            wPath.lineJoinStyle = .round

            // Left vertical line of W
            wPath.move(to: NSPoint(x: 8.5 * scale, y: (24 - 8) * scale))
            wPath.line(to: NSPoint(x: 8.5 * scale, y: (24 - 16) * scale))

            // Right vertical line of W
            wPath.move(to: NSPoint(x: 15.5 * scale, y: (24 - 8) * scale))
            wPath.line(to: NSPoint(x: 15.5 * scale, y: (24 - 16) * scale))

            // Left diagonal to center
            wPath.move(to: NSPoint(x: 8.5 * scale, y: (24 - 16) * scale))
            wPath.line(to: NSPoint(x: 12 * scale, y: (24 - 12) * scale))

            // Right diagonal to center
            wPath.move(to: NSPoint(x: 15.5 * scale, y: (24 - 16) * scale))
            wPath.line(to: NSPoint(x: 12 * scale, y: (24 - 12) * scale))

            wPath.stroke()

            return true
        }

        image.isTemplate = true  // Allows automatic light/dark mode adaptation
        return image
    }

    private func updateStatusMenuItem() {
        guard let menu = statusMenu, let viewModel = viewModel else { return }

        // Find status menu item by tag
        if let statusItem = menu.item(withTag: 100) {
            let activeCount = viewModel.activeBlocks.count
            if activeCount > 0 {
                let domainCount = viewModel.totalDomainsBlocked
                statusItem.title = "Blocking \(domainCount) domain\(domainCount == 1 ? "" : "s")"
            } else {
                statusItem.title = "Status: Ready"
            }
        }
    }

    // MARK: - Actions

    @objc private func menuBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            // Show menu on right-click or Option+click
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
            // Reset menu to nil after showing to allow left-click action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.statusItem?.menu = nil
            }
        } else {
            // Always show/focus window on left-click (never hide)
            showMainWindow()
        }
    }

    @objc func showMainWindow() {
        // Switch to regular app mode (shows in Dock)
        NSApp.setActivationPolicy(.regular)

        // First, try to use our cached mainWindow reference (it may be hidden but still valid)
        if let window = mainWindow {
            showAndFocusWindow(window)
            logger.debug("Showing cached window")
            return
        }

        // No cached window - try to find one in NSApp.windows
        if let window = findMainContentWindow() {
            mainWindow = window
            showAndFocusWindow(window)
            logger.debug("Showing found window")
            return
        }

        // No window exists - request SwiftUI to create one
        logger.debug("No window found - requesting new window")
        requestNewWindow()
    }

    /// Show window and ensure it's focused
    private func showAndFocusWindow(_ window: NSWindow) {
        // Show the window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Ensure app is active and focused
        NSApp.activate(ignoringOtherApps: true)

        // Additional focus calls after a tiny delay to ensure activation completes
        DispatchQueue.main.async {
            window.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }

        isWindowVisible = true
    }

    /// Find the main content window (skip menu bar windows, small windows, etc.)
    private func findMainContentWindow() -> NSWindow? {
        for window in NSApp.windows {
            // Must be able to become main window
            guard window.canBecomeMain else { continue }
            // Skip tiny windows (like invisible helper windows or panels)
            guard window.frame.width > 200 && window.frame.height > 200 else { continue }
            // Skip the status item window
            guard window.className != "NSStatusBarWindow" else { continue }

            return window
        }
        return nil
    }

    /// Request SwiftUI to create a new window
    private func requestNewWindow() {
        // Try standard AppKit mechanism to trigger window creation
        // This triggers the "New Window" menu action in SwiftUI apps
        if #available(macOS 13.0, *) {
            NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil)
        }

        // Check for window after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if let window = self?.findMainContentWindow() {
                self?.mainWindow = window
                self?.showAndFocusWindow(window)
                logger.debug("Window created and shown")
            } else {
                logger.warning("Failed to create window")
            }
        }
    }

    func hideMainWindow() {
        // Hide the window instead of closing it (so we can show it again)
        // orderOut removes from screen but keeps the window object
        mainWindow?.orderOut(nil)

        // Small delay before changing activation policy to avoid visual glitches
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
        }

        isWindowVisible = false
        logger.debug("Window hidden - running in background")
    }

    /// Called by WindowAccessor when window becomes visible
    func windowDidBecomeVisible(_ window: NSWindow) {
        mainWindow = window
        isWindowVisible = true
        NSApp.setActivationPolicy(.regular)
    }

    /// Called from menu bar "Quit Completely" item
    @objc private func quitCompletelyFromMenu() {
        quitCompletely()
    }

    /// Called from SwiftUI menu or programmatically - quits the app with warning if needed
    func quitCompletely() {
        // Check for visit-based triggers that require background monitoring
        if let viewModel = viewModel, viewModel.requiresBackgroundMonitoring {
            showQuitWarningThenTerminate()
        } else {
            // No warning needed - just quit
            viewModel?.stopStateSync()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Quit Warning

    /// Shows warning dialog then terminates if user confirms
    private func showQuitWarningThenTerminate() {
        // Make sure we're in regular mode to show the alert
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Quit Willpower?"
        alert.informativeText = "You have visit-based triggers enabled. If you quit Willpower, browser monitoring will stop and these triggers won't work."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // User confirmed quit - force terminate
            forceQuit()
        } else {
            // User cancelled - go back to accessory mode if window isn't visible
            if !isWindowVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// Force quit without further warnings (bypasses applicationShouldTerminate)
    private func forceQuit() {
        viewModel?.stopStateSync()
        iconUpdateTimer?.invalidate()
        iconUpdateTimer = nil
        // Use exit() to bypass applicationShouldTerminate which might show another warning
        exit(0)
    }
}
