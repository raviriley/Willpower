//
//  UpdaterController.swift
//  Willpower
//
//  Manages automatic updates using Sparkle framework.
//  Provides SwiftUI integration for update checking.
//

import Foundation
import SwiftUI

#if canImport(Sparkle)
import Sparkle

/// Observable controller for Sparkle updates
/// Use this to integrate update checking into SwiftUI views
@MainActor
@Observable
final class UpdaterController {

    // MARK: - Properties

    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater can check for updates
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether to automatically download updates
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Last update check date
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    // MARK: - Initialization

    init() {
        // Initialize the standard Sparkle updater controller
        // This handles all the UI for update prompts
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    // MARK: - Actions

    /// Manually check for updates
    /// Shows the update UI if an update is available
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// SwiftUI view for "Check for Updates" menu item
struct CheckForUpdatesView: View {
    @Environment(UpdaterController.self) private var updaterController

    var body: some View {
        Button("Check for Updates...") {
            updaterController.checkForUpdates()
        }
        .disabled(!updaterController.canCheckForUpdates)
    }
}

/// Settings view for update preferences
struct UpdateSettingsView: View {
    @Environment(UpdaterController.self) private var updaterController

    var body: some View {
        @Bindable var controller = updaterController

        Form {
            Toggle("Automatically check for updates", isOn: $controller.automaticallyChecksForUpdates)

            Toggle("Automatically download updates", isOn: $controller.automaticallyDownloadsUpdates)
                .disabled(!controller.automaticallyChecksForUpdates)

            if let lastCheck = controller.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Check Now") {
                controller.checkForUpdates()
            }
            .disabled(!controller.canCheckForUpdates)
        }
    }
}

#else

// MARK: - Stub Implementation (when Sparkle is not available)

/// Stub controller when Sparkle is not imported
/// This allows the app to compile without Sparkle during development
@MainActor
@Observable
final class UpdaterController {
    var canCheckForUpdates: Bool { false }
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { false }
        set { }
    }
    var lastUpdateCheckDate: Date? { nil }

    init() {
        print("[UpdaterController] Sparkle not available - updates disabled")
    }

    func checkForUpdates() {
        print("[UpdaterController] Sparkle not available")
    }
}

struct CheckForUpdatesView: View {
    var body: some View {
        Button("Check for Updates...") { }
            .disabled(true)
    }
}

struct UpdateSettingsView: View {
    var body: some View {
        Text("Updates not available in this build")
            .foregroundStyle(.secondary)
    }
}

#endif
