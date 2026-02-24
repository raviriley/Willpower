//
//  UpdaterController.swift
//  Willpower
//
//  Manages automatic updates using Sparkle framework.
//  Provides SwiftUI integration for update checking.
//

import AppKit
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
    private let delegateHandler = UpdaterDelegateHandler()
    private var lastGitHubCheck: Date = .distantPast

    /// Whether a newer version is available
    var isUpdateAvailable: Bool = false

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
            updaterDelegate: delegateHandler,
            userDriverDelegate: nil
        )

        delegateHandler.onUpdateFound = { [weak self] in
            Task { @MainActor in self?.isUpdateAvailable = true }
        }
        delegateHandler.onNoUpdateFound = { [weak self] in
            Task { @MainActor in self?.isUpdateAvailable = false }
        }

        Task { await checkLatestVersion() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.checkLatestVersion() }
        }
    }

    // MARK: - Actions

    /// Manually check for updates
    /// Shows the update UI if an update is available
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Lightweight GitHub API check as fallback for Sparkle
    private func checkLatestVersion() async {
        guard Date().timeIntervalSince(lastGitHubCheck) > 300 else { return }
        lastGitHubCheck = Date()
        guard let url = URL(string: "https://api.github.com/repos/raviriley/Willpower/releases/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if remoteVersion.compare(localVersion, options: .numeric) == .orderedDescending {
                isUpdateAvailable = true
            }
        } catch {
            // Silently ignore — Sparkle is the primary mechanism
        }
    }
}

// MARK: - Sparkle Delegate

private class UpdaterDelegateHandler: NSObject, SPUUpdaterDelegate {
    var onUpdateFound: (() -> Void)?
    var onNoUpdateFound: (() -> Void)?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onUpdateFound?()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        onNoUpdateFound?()
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
    var isUpdateAvailable: Bool = false
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
