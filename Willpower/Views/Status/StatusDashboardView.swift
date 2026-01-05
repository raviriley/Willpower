//
//  StatusDashboardView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct StatusDashboardView: View {
    var viewModel: WillpowerViewModel

    /// Find trigger name for a visit-count block (blocklistId is actually pattern.id)
    private func triggerName(for block: ActiveBlock) -> String? {
        guard block.reason == .visitCountTrigger else { return nil }

        // For independent triggers, blocklistId is the pattern.id
        for trigger in viewModel.independentTriggers {
            if trigger.urlPatterns.contains(where: { $0.id == block.blocklistId }) {
                return trigger.name
            }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Stats
                HStack(spacing: 20) {
                    StatCard(
                        title: "Active Blocks",
                        value: "\(viewModel.activeBlocks.count)",
                        icon: "shield.fill",
                        color: viewModel.activeBlocks.isEmpty ? .gray : .red
                    )
                    StatCard(
                        title: "Domains Blocked",
                        value: "\(viewModel.totalDomainsBlocked)",
                        icon: "globe",
                        color: viewModel.totalDomainsBlocked == 0 ? .gray : .orange
                    )
                    StatCard(
                        title: "Blocklists",
                        value: "\(viewModel.blocklists.count)",
                        icon: "list.bullet",
                        color: .accentColor
                    )
                }

                // Active Blocks List
                if !viewModel.activeBlocks.isEmpty {
                    GroupBox("Currently Active") {
                        VStack(spacing: 0) {
                            ForEach(viewModel.activeBlocks) { block in
                                ActiveBlockRowView(
                                    block: block,
                                    blocklist: viewModel.blocklists.first { $0.id == block.blocklistId },
                                    triggerName: triggerName(for: block)
                                )
                                if block.id != viewModel.activeBlocks.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Active Blocks",
                        systemImage: "checkmark.shield",
                        description: Text("All sites are currently accessible")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Status")
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    StatusDashboardView(viewModel: WillpowerViewModel())
}
