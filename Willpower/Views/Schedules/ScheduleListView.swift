//
//  ScheduleListView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

/// Model for editing an existing schedule (used for sheet item binding)
struct ScheduleEditItem: Identifiable {
    let id = UUID()
    let blocklist: BlocklistConfig
    let trigger: TriggerConfig
}

struct ScheduleListView: View {
    @Bindable var viewModel: WillpowerViewModel

    @State private var selectedBlocklistForNewSchedule: BlocklistConfig?
    @State private var scheduleToEdit: ScheduleEditItem?

    var body: some View {
        List {
            ForEach(viewModel.blocklists) { blocklist in
                let schedules = viewModel.scheduleTriggers(for: blocklist)
                if !schedules.isEmpty {
                    Section(blocklist.name) {
                        ForEach(schedules) { trigger in
                            ScheduleRowView(
                                trigger: trigger,
                                blocklist: blocklist,
                                viewModel: viewModel
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                scheduleToEdit = ScheduleEditItem(blocklist: blocklist, trigger: trigger)
                            }
                            .contextMenu {
                                Button("Edit") {
                                    scheduleToEdit = ScheduleEditItem(blocklist: blocklist, trigger: trigger)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    viewModel.removeSchedule(triggerId: trigger.id, from: blocklist)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(viewModel.blocklists) { blocklist in
                        Button(blocklist.name) {
                            selectedBlocklistForNewSchedule = blocklist
                        }
                    }
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                .disabled(viewModel.blocklists.isEmpty)
            }
        }
        // Sheet for creating new schedules
        .sheet(item: $selectedBlocklistForNewSchedule) { blocklist in
            ScheduleEditorSheet(viewModel: viewModel, blocklist: blocklist)
        }
        // Sheet for editing existing schedules
        .sheet(item: $scheduleToEdit) { editItem in
            ScheduleEditorSheet(
                viewModel: viewModel,
                blocklist: editItem.blocklist,
                existingTrigger: editItem.trigger
            )
        }
        .overlay {
            if viewModel.allScheduleTriggers.isEmpty {
                ContentUnavailableView {
                    Label("No Schedules", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Schedules automatically block websites at specific times. Perfect for work hours, study sessions, or bedtime routines.")
                } actions: {
                    if !viewModel.blocklists.isEmpty {
                        Menu("Add Schedule") {
                            ForEach(viewModel.blocklists) { blocklist in
                                Button(blocklist.name) {
                                    selectedBlocklistForNewSchedule = blocklist
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

// MARK: - Schedule Row View

struct ScheduleRowView: View {
    let trigger: TriggerConfig
    let blocklist: BlocklistConfig
    let viewModel: WillpowerViewModel

    /// Check if this schedule is currently active
    var isActive: Bool {
        viewModel.activeBlocks.contains {
            $0.blocklistId == blocklist.id &&
            $0.reason == .scheduleBasedTrigger &&
            !$0.isExpired
        }
    }

    var body: some View {
        HStack {
            Image(systemName: isActive ? "clock.badge.checkmark.fill" : "calendar.badge.clock")
                .foregroundStyle(isActive ? .green : (trigger.isEnabled ? .blue : .gray))
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                if let schedule = trigger.scheduleBased {
                    ForEach(schedule.windows) { window in
                        HStack {
                            Text(window.timeRangeDescription)
                                .font(.subheadline)
                            Text(window.weekdaysDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isActive {
                    Text("Currently active")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ScheduleWindow Extensions

extension ScheduleBasedTrigger.ScheduleWindow {
    var timeRangeDescription: String {
        let startTime = String(format: "%02d:%02d", startHour, startMinute)
        let endTime = String(format: "%02d:%02d", endHour, endMinute)
        return "\(startTime) - \(endTime)"
    }

    var weekdaysDescription: String {
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let sortedDays = weekdays.sorted()

        if weekdays == Self.everyday {
            return "Every day"
        } else if weekdays == Self.weekdaysOnly {
            return "Weekdays"
        } else if weekdays == Self.weekendsOnly {
            return "Weekends"
        } else {
            return sortedDays.map { dayNames[$0] }.joined(separator: ", ")
        }
    }
}

#Preview {
    ScheduleListView(viewModel: WillpowerViewModel())
}
