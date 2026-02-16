//
//  BlocklistListView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct BlocklistListView: View {
    @Bindable var viewModel: WillpowerViewModel
    @State private var blocklistToDelete: BlocklistConfig?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        List(viewModel.regularBlocklists, selection: $viewModel.selectedBlocklistId) { blocklist in
            BlocklistRowView(
                blocklist: blocklist,
                isActive: viewModel.isBlocklistActive(blocklist),
                isLocked: viewModel.isBlocklistLocked(blocklist)
            )
            .tag(blocklist.id)
            .contextMenu {
                Button("Activate...") {
                    viewModel.selectedBlocklistId = blocklist.id
                    viewModel.isShowingActivationSheet = true
                }
                .disabled(viewModel.isBlocklistActive(blocklist))

                Divider()

                Button("Delete", role: .destructive) {
                    blocklistToDelete = blocklist
                    isShowingDeleteConfirmation = true
                }
                .disabled(viewModel.isBlocklistLocked(blocklist))
            }
        }
        .listStyle(.inset)
        .navigationTitle("Blocklists")
        .toolbar {
            ToolbarItem {
                Button(action: { createNewBlocklist() }) {
                    Label("New Blocklist", systemImage: "plus")
                }
            }
        }
        .alert("Delete Blocklist?", isPresented: $isShowingDeleteConfirmation, presenting: blocklistToDelete) { blocklist in
            Button("Cancel", role: .cancel) {
                blocklistToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteBlocklist(blocklist)
                blocklistToDelete = nil
            }
        } message: { blocklist in
            let scheduleCount = blocklist.triggers.filter { $0.type == .scheduleBased }.count
            if scheduleCount > 0 {
                Text("This will also delete \(scheduleCount) schedule(s) attached to \"\(blocklist.name)\". This cannot be undone.")
            } else {
                Text("Are you sure you want to delete \"\(blocklist.name)\"? This cannot be undone.")
            }
        }
        .overlay {
            if viewModel.regularBlocklists.isEmpty {
                ContentUnavailableView {
                    Label("No Blocklists", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Create a blocklist to group distracting websites together. Block them manually or automatically with schedules and triggers.")
                } actions: {
                    Button("Create Blocklist") {
                        createNewBlocklist()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func createNewBlocklist() {
        viewModel.createBlocklist(name: "New Blocklist", domains: [])
    }
}

#Preview {
    BlocklistListView(viewModel: WillpowerViewModel())
}
