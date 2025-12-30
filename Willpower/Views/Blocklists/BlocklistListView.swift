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

    var body: some View {
        List(viewModel.blocklists, selection: $viewModel.selectedBlocklistId) { blocklist in
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
                    viewModel.deleteBlocklist(blocklist)
                }
                .disabled(viewModel.isBlocklistLocked(blocklist))
            }
        }
        .listStyle(.inset)
        .navigationTitle("Blocklists")
        .toolbar {
            ToolbarItem {
                Button(action: { viewModel.isShowingNewBlocklistSheet = true }) {
                    Label("New Blocklist", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingNewBlocklistSheet) {
            BlocklistEditorSheet(viewModel: viewModel, blocklist: nil)
        }
        .overlay {
            if viewModel.blocklists.isEmpty {
                ContentUnavailableView {
                    Label("No Blocklists", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Create a blocklist to start blocking websites")
                } actions: {
                    Button("Create Blocklist") {
                        viewModel.isShowingNewBlocklistSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

#Preview {
    BlocklistListView(viewModel: WillpowerViewModel())
}
