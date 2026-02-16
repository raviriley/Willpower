//
//  WillpowerApp.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit
import AppKit

@main
struct WillpowerApp: App {
    @State private var viewModel = WillpowerViewModel()
    @State private var daemonManager = DaemonManager()
    @State private var updaterController = UpdaterController()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showDaemonSetup = false

    // AppDelegate adapter for menu bar and lifecycle management
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(daemonManager)
                .environment(updaterController)
                .background(WindowAccessor(appDelegate: appDelegate))
                .onAppear {
                    // Configure AppDelegate with our viewModel
                    appDelegate.configure(with: viewModel)
                    viewModel.daemonManager = daemonManager
                    daemonManager.refreshStatus()

                    if !hasCompletedOnboarding {
                        // First-time user: show full onboarding
                        showOnboarding = true
                    } else if !daemonManager.isEnabled {
                        // Returning user but daemon needs setup: show daemon setup only
                        showDaemonSetup = true
                    }
                }
                // NOTE: Removed .onDisappear { viewModel.stopStateSync() }
                // Browser monitoring now continues in background when window closes
                // First-time onboarding (full flow)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(
                        viewModel: viewModel,
                        daemonManager: daemonManager,
                        onComplete: {
                            hasCompletedOnboarding = true
                            showOnboarding = false
                            // Navigate to blocklists and create a new one
                            viewModel.selectedCategory = .blocklists
                            viewModel.createBlocklist(name: "New Blocklist", domains: [])
                        }
                    )
                    .interactiveDismissDisabled()
                }
                // Returning user daemon setup (just step 2)
                .sheet(isPresented: $showDaemonSetup) {
                    DaemonSetupView(daemonManager: daemonManager)
                        .interactiveDismissDisabled(!daemonManager.isEnabled)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
        .commands {
            // Add "Check for Updates" to the app menu
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView()
                    .environment(updaterController)
            }

            // Replace default Quit command - Cmd+Q hides window, keeps app in menu bar
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    appDelegate.hideMainWindow()
                }
                .keyboardShortcut("q", modifiers: .command)

                Divider()

                Button("Quit Completely") {
                    appDelegate.quitCompletely()
                }
                .keyboardShortcut("q", modifiers: [.command, .option])
            }
        }
    }
}

// MARK: - Window Accessor Helper

/// Allows AppDelegate to receive window lifecycle events
struct WindowAccessor: NSViewRepresentable {
    let appDelegate: AppDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.delegate = context.coordinator
                // Notify AppDelegate that window is visible
                appDelegate.windowDidBecomeVisible(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update window delegate if window changed
        if let window = nsView.window, window.delegate !== context.coordinator {
            window.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appDelegate: appDelegate)
    }

    class Coordinator: NSObject, NSWindowDelegate {
        let appDelegate: AppDelegate

        init(appDelegate: AppDelegate) {
            self.appDelegate = appDelegate
        }

        /// Intercept window close (red X button) - hide instead of close
        func windowShouldClose(_ window: NSWindow) -> Bool {
            Task { @MainActor in
                appDelegate.hideMainWindow()
            }
            // Return false to prevent actual close - we just hide it
            return false
        }

        func windowDidBecomeKey(_ notification: Notification) {
            if let window = notification.object as? NSWindow {
                Task { @MainActor in
                    appDelegate.windowDidBecomeVisible(window)
                }
            }
        }
    }
}
