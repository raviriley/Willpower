//
//  BlocklistDetailView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct BlocklistDetailView: View {
    @Bindable var viewModel: WillpowerViewModel
    let blocklistId: UUID

    @State private var isShowingEditor = false

    /// Get the current blocklist from viewModel (always fresh)
    var blocklist: BlocklistConfig? {
        viewModel.blocklists.first { $0.id == blocklistId }
    }

    var activeBlock: ActiveBlock? {
        guard let blocklist else { return nil }
        return viewModel.activeBlock(for: blocklist)
    }

    var body: some View {
        Group {
            if let blocklist {
                Form {
                    // Basic Info Section
                    Section("Blocklist") {
                        LabeledContent("Name", value: blocklist.name)
                        LabeledContent("Created", value: blocklist.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Last Updated", value: blocklist.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    // Domains Section
                    Section("Blocked Domains (\(blocklist.domains.count))") {
                        if blocklist.domains.isEmpty {
                            Text("No domains configured")
                                .foregroundStyle(.secondary)
                                .italic()
                        } else {
                            ForEach(blocklist.domains, id: \.self) { domain in
                                Text(domain)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }

                    // Status Section
                    Section("Status") {
                        if let activeBlock {
                            LabeledContent("Status") {
                                StatusBadge(
                                    text: activeBlock.isLocked ? "LOCKED" : "ACTIVE",
                                    color: activeBlock.isLocked ? .red : .orange
                                )
                            }
                            if let expiresAt = activeBlock.expiresAt {
                                LabeledContent("Expires in") {
                                    TimeRemainingView(expiresAt: expiresAt)
                                }
                            } else {
                                LabeledContent("Expires", value: "Indefinite")
                            }
                            LabeledContent("Reason", value: activeBlock.reason.displayName)
                        } else {
                            LabeledContent("Status", value: "Inactive")
                        }
                    }

                    // Triggers Section
                    if !blocklist.triggers.isEmpty {
                        Section("Configured Triggers") {
                            ForEach(blocklist.triggers) { trigger in
                                TriggerSummaryRow(trigger: trigger)
                            }
                        }
                    }

                    // Actions Section
                    Section("Actions") {
                        if let activeBlock {
                            if activeBlock.isLocked {
                                HStack {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.red)
                                    Text("Block is locked and cannot be deactivated until it expires")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button("Deactivate", role: .destructive) {
                                    viewModel.deactivateBlocklist(blocklist)
                                }
                            }
                        } else {
                            Button("Activate Now...") {
                                viewModel.isShowingActivationSheet = true
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(blocklist.name)
                .toolbar {
                    ToolbarItem {
                        Button("Edit") {
                            isShowingEditor = true
                        }
                    }
                }
                .sheet(isPresented: $isShowingEditor) {
                    BlocklistEditorSheet(viewModel: viewModel, blocklist: blocklist)
                }
                .sheet(isPresented: $viewModel.isShowingActivationSheet) {
                    ManualActivationSheet(viewModel: viewModel, blocklistId: blocklistId)
                }
            } else {
                ContentUnavailableView(
                    "Blocklist Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This blocklist may have been deleted")
                )
            }
        }
    }
}

// MARK: - Trigger Summary Row

struct TriggerSummaryRow: View {
    let trigger: TriggerConfig

    var body: some View {
        HStack {
            Image(systemName: trigger.type.icon)
                .foregroundStyle(trigger.isEnabled ? .blue : .gray)

            VStack(alignment: .leading) {
                Text(trigger.type.displayName)
                    .font(.subheadline)

                Text(trigger.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !trigger.isEnabled {
                Text("Disabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - TriggerType Extensions

extension TriggerType {
    var icon: String {
        switch self {
        case .timeBased: return "clock"
        case .scheduleBased: return "calendar.badge.clock"
        case .visitCount: return "eye"
        }
    }

    var displayName: String {
        switch self {
        case .timeBased: return "Time-Based"
        case .scheduleBased: return "Scheduled"
        case .visitCount: return "Visit Count"
        }
    }
}

// MARK: - TriggerConfig Summary

extension TriggerConfig {
    var summary: String {
        switch type {
        case .timeBased:
            if let tb = timeBased {
                if let duration = tb.durationSeconds {
                    return formatDuration(duration)
                } else if let endTime = tb.endTime {
                    return "Until \(endTime.formatted(date: .omitted, time: .shortened))"
                }
            }
            return "Not configured"

        case .scheduleBased:
            if let sb = scheduleBased {
                let windowCount = sb.windows.count
                return "\(windowCount) schedule window\(windowCount == 1 ? "" : "s")"
            }
            return "Not configured"

        case .visitCount:
            if let vc = visitCount {
                return "After \(vc.maxVisits) visits, block for \(formatDuration(vc.blockDurationSeconds))"
            }
            return "Not configured"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }
}

#Preview {
    let viewModel = WillpowerViewModel()
    let blocklist = BlocklistConfig(
        name: "Social Media",
        domains: ["twitter.com", "facebook.com", "instagram.com"]
    )
    viewModel.blocklists.append(blocklist)
    viewModel.selectedBlocklistId = blocklist.id

    return NavigationStack {
        BlocklistDetailView(
            viewModel: viewModel,
            blocklistId: blocklist.id
        )
    }
}
