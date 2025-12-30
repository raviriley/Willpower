//
//  TriggerListView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

/// Model for editing an existing trigger (used for sheet item binding)
struct TriggerEditItem: Identifiable {
    let id = UUID()
    let blocklist: BlocklistConfig
    let trigger: TriggerConfig
}

struct TriggerListView: View {
    @Bindable var viewModel: WillpowerViewModel

    @State private var selectedBlocklistForNewTrigger: BlocklistConfig?
    @State private var triggerToEdit: TriggerEditItem?

    var body: some View {
        List {
            ForEach(viewModel.blocklists) { blocklist in
                let triggers = viewModel.visitCountTriggers(for: blocklist)
                if !triggers.isEmpty {
                    Section(blocklist.name) {
                        ForEach(triggers) { trigger in
                            TriggerRowView(
                                trigger: trigger,
                                blocklist: blocklist,
                                viewModel: viewModel
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                triggerToEdit = TriggerEditItem(blocklist: blocklist, trigger: trigger)
                            }
                            .contextMenu {
                                Button("Edit") {
                                    triggerToEdit = TriggerEditItem(blocklist: blocklist, trigger: trigger)
                                }
                                Button("Reset Visit Count") {
                                    if let vc = trigger.visitCount {
                                        let patternIds = vc.urlPatterns.map { $0.id }
                                        viewModel.resetVisitCounts(patternIds: patternIds)
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    viewModel.removeVisitTrigger(triggerId: trigger.id, from: blocklist)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Triggers")
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(viewModel.blocklists) { blocklist in
                        Button(blocklist.name) {
                            selectedBlocklistForNewTrigger = blocklist
                        }
                    }
                } label: {
                    Label("Add Trigger", systemImage: "plus")
                }
                .disabled(viewModel.blocklists.isEmpty)
            }
        }
        // Sheet for creating new triggers
        .sheet(item: $selectedBlocklistForNewTrigger) { blocklist in
            TriggerEditorSheet(viewModel: viewModel, blocklist: blocklist)
        }
        // Sheet for editing existing triggers
        .sheet(item: $triggerToEdit) { editItem in
            TriggerEditorSheet(
                viewModel: viewModel,
                blocklist: editItem.blocklist,
                existingTrigger: editItem.trigger
            )
        }
        .overlay {
            if viewModel.allVisitCountTriggers.isEmpty {
                ContentUnavailableView {
                    Label("No Triggers", systemImage: "eye.trianglebadge.exclamationmark")
                } description: {
                    Text("Create a visit-count trigger to automatically block sites after too many visits")
                } actions: {
                    if !viewModel.blocklists.isEmpty {
                        Menu("Add Trigger") {
                            ForEach(viewModel.blocklists) { blocklist in
                                Button(blocklist.name) {
                                    selectedBlocklistForNewTrigger = blocklist
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Create a blocklist first")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Trigger Row View

struct TriggerRowView: View {
    let trigger: TriggerConfig
    let blocklist: BlocklistConfig
    let viewModel: WillpowerViewModel

    /// Check if this trigger is currently active (caused a block)
    var isActive: Bool {
        viewModel.activeBlocks.contains {
            $0.blocklistId == blocklist.id &&
            $0.reason == .visitCountTrigger &&
            !$0.isExpired
        }
    }

    var body: some View {
        HStack {
            Image(systemName: isActive ? "exclamationmark.triangle.fill" : "eye.trianglebadge.exclamationmark")
                .foregroundStyle(isActive ? .red : (trigger.isEnabled ? .orange : .gray))
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                if let vc = trigger.visitCount {
                    ForEach(vc.urlPatterns) { pattern in
                        HStack {
                            Text(pattern.pattern)
                                .font(.system(.subheadline, design: .monospaced))

                            if let record = viewModel.visitRecords.first(where: { $0.patternId == pattern.id }) {
                                Text("\(record.visitCount)/\(vc.maxVisits)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(visitCountColor(record.visitCount, max: vc.maxVisits).opacity(0.2))
                                    .foregroundStyle(visitCountColor(record.visitCount, max: vc.maxVisits))
                                    .clipShape(Capsule())
                            } else {
                                Text("0/\(vc.maxVisits)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if isActive {
                        Text("Threshold reached - blocklist active")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Block for \(formatDuration(vc.blockDurationSeconds)) when threshold reached")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func visitCountColor(_ count: Int, max: Int) -> Color {
        let ratio = Double(count) / Double(max)
        if ratio >= 1.0 {
            return .red
        } else if ratio >= 0.7 {
            return .orange
        } else if ratio >= 0.4 {
            return .yellow
        } else {
            return .green
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
    TriggerListView(viewModel: WillpowerViewModel())
}
