//
//  TriggerListView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct TriggerListView: View {
    @Bindable var viewModel: WillpowerViewModel

    @State private var isShowingNewTrigger = false
    @State private var triggerToEdit: IndependentTrigger?
    @State private var triggerToDelete: IndependentTrigger?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        List {
            ForEach(viewModel.independentTriggers) { trigger in
                TriggerRowView(trigger: trigger, viewModel: viewModel)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        triggerToEdit = trigger
                    }
                    .contextMenu {
                        Button("Edit") {
                            triggerToEdit = trigger
                        }
                        Button("Reset Visit Count") {
                            let patternIds = trigger.urlPatterns.map { $0.id }
                            viewModel.resetVisitCounts(patternIds: patternIds)
                        }
                        Button(trigger.isEnabled ? "Disable" : "Enable") {
                            var updated = trigger
                            updated.isEnabled.toggle()
                            viewModel.updateIndependentTrigger(updated)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            triggerToDelete = trigger
                            isShowingDeleteConfirmation = true
                        }
                    }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Triggers")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingNewTrigger = true
                } label: {
                    Label("Add Trigger", systemImage: "plus")
                }
            }
        }
        // Sheet for creating new triggers
        .sheet(isPresented: $isShowingNewTrigger) {
            TriggerEditorSheet(viewModel: viewModel)
        }
        // Sheet for editing existing triggers
        .sheet(item: $triggerToEdit) { trigger in
            TriggerEditorSheet(viewModel: viewModel, existingTrigger: trigger)
        }
        .alert("Delete Trigger?", isPresented: $isShowingDeleteConfirmation, presenting: triggerToDelete) { trigger in
            Button("Cancel", role: .cancel) {
                triggerToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteIndependentTrigger(trigger)
                triggerToDelete = nil
            }
        } message: { trigger in
            Text("Are you sure you want to delete \"\(trigger.name)\"? This will also delete all visit history. This cannot be undone.")
        }
        .overlay {
            if viewModel.independentTriggers.isEmpty {
                ContentUnavailableView {
                    Label("No Triggers", systemImage: "eye.trianglebadge.exclamationmark")
                } description: {
                    Text("Triggers monitor your browsing and automatically block websites after too many visits. Great for limiting time on addictive sites without blocking them entirely.")
                } actions: {
                    Button("Add Trigger") {
                        isShowingNewTrigger = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - Trigger Row View

struct TriggerRowView: View {
    let trigger: IndependentTrigger
    let viewModel: WillpowerViewModel

    /// Check if this trigger is currently active (caused a block)
    var isActive: Bool {
        for pattern in trigger.urlPatterns {
            if viewModel.activeBlocks.contains(where: { $0.blocklistId == pattern.id && !$0.isExpired }) {
                return true
            }
        }
        return false
    }

    /// Total visits for this trigger
    var totalVisits: Int {
        trigger.urlPatterns.reduce(0) { sum, pattern in
            if let record = viewModel.visitRecords.first(where: { $0.patternId == pattern.id }) {
                return sum + record.visitCount
            }
            return sum
        }
    }

    var body: some View {
        HStack {
            Image(systemName: isActive ? "exclamationmark.triangle.fill" : "eye.trianglebadge.exclamationmark")
                .foregroundStyle(isActive ? .red : (trigger.isEnabled ? .orange : .gray))
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(trigger.name)
                        .font(.headline)

                    if !trigger.isEnabled {
                        Text("Disabled")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                // Show patterns with visit counts
                ForEach(trigger.urlPatterns) { pattern in
                    HStack(spacing: 4) {
                        Text(pattern.pattern)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(blockActionBadge(for: pattern))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    // Visit count badge
                    Text("\(totalVisits)/\(trigger.maxVisits)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(visitCountColor(totalVisits, max: trigger.maxVisits).opacity(0.2))
                        .foregroundStyle(visitCountColor(totalVisits, max: trigger.maxVisits))
                        .clipShape(Capsule())

                    if isActive {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Block for \(formatDuration(trigger.blockDurationSeconds))")
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

    private func blockActionBadge(for pattern: URLPattern) -> String {
        switch pattern.blockAction {
        case .blockDomain:
            return "→ \(pattern.associatedDomain)"
        case .activateBlocklist(let blocklistId):
            if let blocklist = viewModel.blocklists.first(where: { $0.id == blocklistId }) {
                return "→ \(blocklist.name)"
            }
            return "→ blocklist"
        }
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
