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

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $viewModel.selectedCategory)
        } content: {
            ContentListView(viewModel: viewModel)
        } detail: {
            DetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                DaemonStatusIndicator(isRunning: viewModel.isDaemonRunning)
            }
        }
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

    var body: some View {
        Group {
            switch viewModel.selectedCategory {
            case .status:
                StatusDashboardView(viewModel: viewModel)
            case .blocklists:
                BlocklistListView(viewModel: viewModel)
            case .schedules:
                ScheduleListView(viewModel: viewModel)
            case .triggers:
                TriggerListView(viewModel: viewModel)
            case .settings:
                SettingsListView(viewModel: viewModel)
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
            case .schedules:
                ScheduleDetailPlaceholder()
            case .triggers:
                TriggerDetailPlaceholder()
            case .settings:
                SettingsDetailPlaceholder()
            }
        }
    }
}

// MARK: - Placeholder Views (temporary)

struct ScheduleDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Schedule",
            systemImage: "calendar.badge.clock",
            description: Text("Choose a schedule to view or edit")
        )
    }
}

struct TriggerDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Select a Trigger",
            systemImage: "eye.trianglebadge.exclamationmark",
            description: Text("Choose a trigger to view or edit")
        )
    }
}

struct SettingsListView: View {
    var viewModel: WillpowerViewModel

    var body: some View {
        List {
            NavigationLink {
                Text("General Settings")
            } label: {
                Label("General", systemImage: "gear")
            }
            NavigationLink {
                Text("Daemon Settings")
            } label: {
                Label("Daemon", systemImage: "server.rack")
            }
            NavigationLink {
                Text("Permissions")
            } label: {
                Label("Permissions", systemImage: "lock.shield")
            }
        }
        .listStyle(.sidebar)
    }
}

struct SettingsDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gear",
            description: Text("Select a settings category")
        )
    }
}

struct ActiveBlocksDetailView: View {
    var viewModel: WillpowerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.activeBlocks) { block in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            if let blocklist = viewModel.blocklists.first(where: { $0.id == block.blocklistId }) {
                                Text(blocklist.name)
                                    .font(.headline)
                            }

                            Text("\(block.domains.count) domains blocked")
                                .foregroundStyle(.secondary)

                            if let expiresAt = block.expiresAt {
                                HStack {
                                    Text("Expires:")
                                    TimeRemainingView(expiresAt: expiresAt)
                                }
                            }

                            if block.isLocked {
                                StatusBadge(text: "LOCKED", color: .red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView(viewModel: WillpowerViewModel())
}
