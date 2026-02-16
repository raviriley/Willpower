//
//  SettingsView.swift
//  Willpower
//
//  Created by Ravi Riley on 1/1/26.
//

import SwiftUI
import ServiceManagement
import WillpowerKit
import AppKit
import UniformTypeIdentifiers
import os.log

private let logger = WillpowerLogger.settings

struct SettingsView: View {
    @Bindable var viewModel: WillpowerViewModel
    @Bindable var daemonManager: DaemonManager

    @State private var isShowingResetConfirmation = false
    @State private var isShowingExportSheet = false
    @State private var isShowingImportSheet = false
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            // MARK: - Status Section
            Section {
                HStack {
                    Label("Blocking Status", systemImage: viewModel.activeBlocks.isEmpty ? "shield" : "shield.fill")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(blockingStatusColor)
                            .frame(width: 8, height: 8)
                        Text(blockingStatusText)
                            .foregroundStyle(blockingStatusColor)
                    }
                }

                if !viewModel.isDaemonRunning {
                    HStack {
                        Text("The daemon is not running. Website blocking is inactive.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reinstall") {
                            daemonManager.register()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else if viewModel.daemonVersion != nil && viewModel.daemonVersion != appVersionShort {
                    HStack {
                        Text("Daemon version (\(viewModel.daemonVersion!)) differs from app (\(appVersionShort))")
                            .font(.callout)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Update Daemon") {
                            daemonManager.update()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let lastHeartbeat = viewModel.lastDaemonHeartbeat {
                    HStack {
                        Label("Last Active", systemImage: "clock")
                        Spacer()
                        Text(lastHeartbeat, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Status")
            }

            // MARK: - Preferences Section
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Label("Launch at Login", systemImage: "power")
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Willpower runs in the menu bar to monitor browser visits. Click the shield icon to open the main window.")
            }

            // MARK: - Data Section
            Section {
                Button {
                    exportData()
                } label: {
                    Label("Export Data", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)

                Button {
                    isShowingImportSheet = true
                } label: {
                    Label("Import Data", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    isShowingResetConfirmation = true
                } label: {
                    Label("Reset All Data", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(hasLockedBlocks)
            } header: {
                Text("Data")
            } footer: {
                if hasLockedBlocks {
                    Text("Cannot reset data while locked blocks are active.")
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }

            // MARK: - About Section
            Section {
                Link(destination: URL(string: "https://x.com/ravi_riley")!) {
                    HStack {
                        Label("Created by Ravi Riley", systemImage: "person.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderless)

                HStack {
                    Label("App Version", systemImage: "info.circle")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                if let daemonVersion = viewModel.daemonVersion {
                    HStack {
                        Label("Daemon Version", systemImage: "server.rack")
                        Spacer()
                        Text(daemonVersion)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label("Blocklists", systemImage: "list.bullet.rectangle")
                    Spacer()
                    Text("\(viewModel.regularBlocklists.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Allowlists", systemImage: "checkmark.shield")
                    Spacer()
                    Text("\(viewModel.allowLists.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Triggers", systemImage: "eye.trianglebadge.exclamationmark")
                    Spacer()
                    Text("\(viewModel.independentTriggers.count)")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/raviriley/Willpower")!) {
                    Label("View on GitHub", systemImage: "link")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            loadLaunchAtLoginState()
        }
        .alert("Reset All Data?", isPresented: $isShowingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAllData()
            }
        } message: {
            Text("This will delete all blocklists, triggers, and visit history. This action cannot be undone.")
        }
        .fileImporter(
            isPresented: $isShowingImportSheet,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - Computed Properties

    private var blockingStatusColor: Color {
        if viewModel.isDaemonRunning {
            return viewModel.activeBlocks.isEmpty ? .green : .blue
        }
        return .red
    }

    private var blockingStatusText: String {
        if viewModel.isDaemonRunning {
            if viewModel.activeBlocks.isEmpty {
                return "Ready"
            } else {
                return "Blocking \(viewModel.totalDomainsBlocked) domains"
            }
        }
        return "Not Blocking"
    }

    private var hasLockedBlocks: Bool {
        viewModel.activeBlocks.contains { $0.isLocked && !$0.isExpired }
    }

    private var appVersionShort: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appVersion: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(appVersionShort) (\(build))"
    }

    // MARK: - Actions

    private func loadLaunchAtLoginState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to set launch at login: \(error.localizedDescription)")
            // Revert the toggle
            launchAtLogin = !enabled
        }
    }

    private func exportData() {
        let export = ExportData(
            blocklists: viewModel.blocklists,
            triggers: viewModel.independentTriggers,
            exportedAt: Date()
        )

        guard let jsonData = try? JSONEncoder().encode(export),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "willpower-backup.json"
        panel.title = "Export Data"

        if panel.runModal() == .OK, let url = panel.url {
            try? jsonString.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else {
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url),
              let importData = try? JSONDecoder().decode(ExportData.self, from: data) else {
            viewModel.errorMessage = "Failed to import: Invalid file format"
            return
        }

        // Merge imported blocklists (avoid duplicates by name+mode pair)
        // Import full blocklist including triggers/schedules
        for blocklist in importData.blocklists {
            if !viewModel.blocklists.contains(where: { $0.name == blocklist.name && $0.mode == blocklist.mode }) {
                viewModel.importBlocklist(blocklist)
            }
        }

        // Merge imported triggers (avoid duplicates by name)
        for trigger in importData.triggers {
            if !viewModel.independentTriggers.contains(where: { $0.name == trigger.name }) {
                viewModel.createIndependentTrigger(trigger)
            }
        }
    }

    private func resetAllData() {
        // Delete all blocklists
        for blocklist in viewModel.blocklists {
            viewModel.deleteBlocklist(blocklist)
        }

        // Delete all triggers
        for trigger in viewModel.independentTriggers {
            viewModel.deleteIndependentTrigger(trigger)
        }
    }
}

// MARK: - Export Data Model

private struct ExportData: Codable {
    let blocklists: [BlocklistConfig]
    let triggers: [IndependentTrigger]
    let exportedAt: Date
}

#Preview {
    SettingsView(viewModel: WillpowerViewModel(), daemonManager: DaemonManager())
}
