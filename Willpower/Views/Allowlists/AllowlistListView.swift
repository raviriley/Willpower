//
//  AllowlistListView.swift
//  Willpower
//
//  Created by Ravi Riley on 2/16/26.
//

import SwiftUI
import WillpowerKit

struct AllowlistListView: View {
    @Bindable var viewModel: WillpowerViewModel
    @State private var allowlistToDelete: BlocklistConfig?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        List(viewModel.allowLists, selection: $viewModel.selectedAllowlistId) { allowlist in
            AllowlistRowView(
                allowlist: allowlist,
                isActive: viewModel.isBlocklistActive(allowlist),
                isLocked: viewModel.isBlocklistLocked(allowlist)
            )
            .tag(allowlist.id)
            .contextMenu {
                Button("Activate...") {
                    viewModel.selectedAllowlistId = allowlist.id
                    viewModel.isShowingAllowlistActivationSheet = true
                }
                .disabled(viewModel.isBlocklistActive(allowlist) || allowlist.domains.isEmpty)

                Divider()

                Button("Delete", role: .destructive) {
                    allowlistToDelete = allowlist
                    isShowingDeleteConfirmation = true
                }
                .disabled(viewModel.isBlocklistLocked(allowlist))
            }
        }
        .listStyle(.inset)
        .navigationTitle("Allowlists")
        .toolbar {
            ToolbarItem {
                Button(action: { createNewAllowlist() }) {
                    Label("New Allowlist", systemImage: "plus")
                }
            }
        }
        .alert("Delete Allowlist?", isPresented: $isShowingDeleteConfirmation, presenting: allowlistToDelete) { allowlist in
            Button("Cancel", role: .cancel) {
                allowlistToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteBlocklist(allowlist)
                allowlistToDelete = nil
            }
        } message: { allowlist in
            Text("Are you sure you want to delete \"\(allowlist.name)\"? This cannot be undone.")
        }
        .overlay {
            if viewModel.allowLists.isEmpty {
                ContentUnavailableView {
                    Label("No Allowlists", systemImage: "checkmark.shield")
                } description: {
                    Text("An allow list restricts browsing to only the domains you specify. Everything else is blocked.")
                } actions: {
                    Button("Create Allowlist") {
                        createNewAllowlist()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
    }

    private func createNewAllowlist() {
        viewModel.createAllowlist(name: "New Allowlist", domains: [])
    }
}

#Preview {
    AllowlistListView(viewModel: WillpowerViewModel())
}
