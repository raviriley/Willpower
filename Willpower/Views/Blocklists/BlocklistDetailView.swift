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
    @State private var isShowingDeactivateConfirmation = false

    /// Get the current blocklist from viewModel (always fresh)
    var blocklist: BlocklistConfig? {
        viewModel.blocklists.first { $0.id == blocklistId }
    }

    var activeBlock: ActiveBlock? {
        guard let blocklist else { return nil }
        return viewModel.activeBlock(for: blocklist)
    }

    /// Independent triggers that target this blocklist
    var targetingTriggers: [IndependentTrigger] {
        guard let blocklist else { return [] }
        return viewModel.independentTriggers.filter { trigger in
            trigger.urlPatterns.contains { pattern in
                if case .activateBlocklist(let targetId) = pattern.blockAction {
                    return targetId == blocklist.id
                }
                return false
            }
        }
    }

    var body: some View {
        Group {
            if let blocklist {
                Form {
                    // Status & Actions Section (combined)
                    Section {
                        if let activeBlock {
                            // Active state UI
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        StatusBadge(
                                            text: activeBlock.isLocked ? "LOCKED" : "ACTIVE",
                                            color: activeBlock.isLocked ? .red : .orange
                                        )
                                        Text(activeBlock.reason.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let expiresAt = activeBlock.expiresAt {
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TimeRemainingView(expiresAt: expiresAt)
                                        }
                                    } else {
                                        Text("Indefinite duration")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if activeBlock.isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            if activeBlock.isLocked {
                                Label {
                                    Text("This block cannot be deactivated until it expires")
                                        .font(.callout)
                                } icon: {
                                    Image(systemName: "info.circle")
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Button("Deactivate Block", role: .destructive) {
                                    isShowingDeactivateConfirmation = true
                                }
                            }
                        } else {
                            // Inactive state UI
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Inactive")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("This blocklist is not currently blocking any domains")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            
                            Button {
                                viewModel.isShowingActivationSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Activate Now")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }

                    // Triggers Section
                    Section {
                        if blocklist.triggers.isEmpty && targetingTriggers.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "bolt.slash")
                                        .foregroundStyle(.secondary)
                                    Text("No triggers configured")
                                        .foregroundStyle(.secondary)
                                }
                                Text("Triggers automatically activate this blocklist based on schedules or visit counts.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            // Embedded triggers (schedules, etc.)
                            ForEach(blocklist.triggers) { trigger in
                                TriggerSummaryRow(
                                    trigger: trigger,
                                    blocklist: blocklist,
                                    viewModel: viewModel
                                )
                            }

                            // Independent triggers that target this blocklist
                            ForEach(targetingTriggers) { trigger in
                                IndependentTriggerSummaryRow(
                                    trigger: trigger,
                                    viewModel: viewModel
                                )
                            }
                        }
                    } header: {
                        Text("Triggers")
                            .padding(.leading, -8)
                    }

                    // Domains Section
                    Section {
                        if blocklist.domains.isEmpty {
                            HStack {
                                Image(systemName: "globe.badge.chevron.backward")
                                    .foregroundStyle(.secondary)
                                Text("No domains configured")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(blocklist.domains, id: \.self) { domain in
                                Text(domain)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    } header: {
                        Text("Blocked Domains (\(blocklist.domains.count))")
                            .padding(.leading, -8)
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
                .alert("Deactivate Block?", isPresented: $isShowingDeactivateConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Deactivate", role: .destructive) {
                        viewModel.deactivateBlocklist(blocklist)
                    }
                } message: {
                    Text("This will immediately unblock all domains in \"\(blocklist.name)\". Are you sure?")
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
    let blocklist: BlocklistConfig
    @Bindable var viewModel: WillpowerViewModel

    var body: some View {
        Button {
            navigateToTrigger()
        } label: {
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
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func navigateToTrigger() {
        switch trigger.type {
        case .scheduleBased:
            // Navigate to Schedules and open editor for this schedule
            viewModel.pendingScheduleToEdit = (blocklist: blocklist, trigger: trigger)
            viewModel.selectedCategory = .schedules
            
        case .visitCount:
            // Navigate to Triggers page
            // Note: blocklist visit-count triggers are different from independent triggers
            // Just navigate to the page for now
            viewModel.selectedCategory = .triggers
            
        case .timeBased:
            // Time-based triggers are typically one-off activations, not persistent configs
            // No specific navigation needed
            break
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
            if let sb = scheduleBased, let window = sb.windows.first {
                return "\(window.timeRangeDescription) \(window.weekdaysDescription)"
            }
            return "Not configured"

        case .visitCount:
            if let vc = visitCount {
                let visitWord = vc.maxVisits == 1 ? "visit" : "visits"
                return "After \(vc.maxVisits) \(visitWord), block for \(formatDuration(vc.blockDurationSeconds))"
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

// MARK: - Independent Trigger Summary Row

struct IndependentTriggerSummaryRow: View {
    let trigger: IndependentTrigger
    @Bindable var viewModel: WillpowerViewModel

    var body: some View {
        Button {
            // Navigate to Triggers page and open editor for this trigger
            viewModel.pendingTriggerToEdit = trigger
            viewModel.selectedCategory = .triggers
        } label: {
            HStack {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .foregroundStyle(trigger.isEnabled ? .orange : .gray)

                VStack(alignment: .leading) {
                    Text(trigger.name)
                        .font(.subheadline)

                    Text(triggerSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !trigger.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var triggerSummary: String {
        let visitWord = trigger.maxVisits == 1 ? "visit" : "visits"
        return "After \(trigger.maxVisits) \(visitWord), block for \(formatDuration(trigger.blockDurationSeconds))"
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
