//
//  ContentView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct ContentView: View {
    @Bindable var viewModel: WillpowerViewModel
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(UpdaterController.self) private var updaterController

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $viewModel.selectedCategory, isDaemonRunning: viewModel.isDaemonRunning, isUpdateAvailable: updaterController.isUpdateAvailable)
        } content: {
            ContentListView(viewModel: viewModel, daemonManager: daemonManager)
        } detail: {
            DetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Content List View

struct ContentListView: View {
    @Bindable var viewModel: WillpowerViewModel
    @Bindable var daemonManager: DaemonManager

    var body: some View {
        Group {
            switch viewModel.selectedCategory {
            case .status:
                StatusDashboardView(viewModel: viewModel)
            case .blocklists:
                BlocklistListView(viewModel: viewModel)
            case .allowlists:
                AllowlistListView(viewModel: viewModel)
            case .schedules:
                ScheduleListView(viewModel: viewModel)
            case .triggers:
                TriggerListView(viewModel: viewModel)
            case .settings:
                SettingsView(viewModel: viewModel, daemonManager: daemonManager)
            }
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 300)
    }
}

// MARK: - Detail View

struct DetailView: View {
    @Bindable var viewModel: WillpowerViewModel

    var body: some View {
        Group {
            switch viewModel.selectedCategory {
            case .status:
                if viewModel.activeBlocks.isEmpty {
                    ContentUnavailableView(
                        "No Active Blocks",
                        systemImage: "checkmark.shield",
                        description: Text("All sites are currently accessible")
                    )
                } else {
                    ActiveBlocksDetailView(viewModel: viewModel)
                }
            case .blocklists:
                if let blocklistId = viewModel.selectedBlocklistId {
                    BlocklistDetailView(viewModel: viewModel, blocklistId: blocklistId)
                } else {
                    ContentUnavailableView(
                        "Select a Blocklist",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Choose a blocklist from the list to view details")
                    )
                }
            case .allowlists:
                if let allowlistId = viewModel.selectedAllowlistId {
                    AllowlistDetailView(viewModel: viewModel, allowlistId: allowlistId)
                } else {
                    ContentUnavailableView(
                        "Select an Allow List",
                        systemImage: "checkmark.shield",
                        description: Text("Choose an allow list from the list to view details")
                    )
                }
            case .schedules:
                ScheduleDetailView(viewModel: viewModel)
            case .triggers:
                TriggerDetailView(viewModel: viewModel)
            case .settings:
                EmptyView()
            }
        }
    }
}

#Preview {
    ContentView(viewModel: WillpowerViewModel())
        .environment(DaemonManager())
        .environment(UpdaterController())
}
