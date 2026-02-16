//
//  ScheduleListView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct ScheduleListView: View {
    @Bindable var viewModel: WillpowerViewModel

    var body: some View {
        List(selection: Binding(
            get: {
                if let ids = viewModel.selectedScheduleId {
                    return "\(ids.blocklistId.uuidString):\(ids.triggerId.uuidString)"
                }
                return nil
            },
            set: { newValue in
                if let value = newValue {
                    let parts = value.split(separator: ":")
                    if parts.count == 2,
                       let blocklistId = UUID(uuidString: String(parts[0])),
                       let triggerId = UUID(uuidString: String(parts[1])) {
                        viewModel.selectedScheduleId = (blocklistId: blocklistId, triggerId: triggerId)
                    }
                } else {
                    viewModel.selectedScheduleId = nil
                }
            }
        )) {
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
                            .tag("\(blocklist.id.uuidString):\(trigger.id.uuidString)")
                            .contextMenu {
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
        .task {
            handlePendingNavigation()
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    if !viewModel.regularBlocklists.isEmpty {
                        Section("Blocklists") {
                            ForEach(viewModel.regularBlocklists) { blocklist in
                                Button(blocklist.name) {
                                    createNewSchedule(for: blocklist)
                                }
                            }
                        }
                    }
                    if !viewModel.allowLists.isEmpty {
                        Section("Allowlists") {
                            ForEach(viewModel.allowLists) { blocklist in
                                Button(blocklist.name) {
                                    createNewSchedule(for: blocklist)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                .disabled(viewModel.blocklists.isEmpty)
            }
        }
        .overlay {
            if viewModel.allScheduleTriggers.isEmpty {
                ContentUnavailableView {
                    Label("No Schedules", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Schedules automatically activate blocklists or allowlists at specific times. Perfect for work hours, study sessions, or bedtime routines.")
                } actions: {
                    if !viewModel.blocklists.isEmpty {
                        Menu("Add Schedule") {
                            if !viewModel.regularBlocklists.isEmpty {
                                Section("Blocklists") {
                                    ForEach(viewModel.regularBlocklists) { blocklist in
                                        Button(blocklist.name) {
                                            createNewSchedule(for: blocklist)
                                        }
                                    }
                                }
                            }
                            if !viewModel.allowLists.isEmpty {
                                Section("Allowlists") {
                                    ForEach(viewModel.allowLists) { blocklist in
                                        Button(blocklist.name) {
                                            createNewSchedule(for: blocklist)
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Create a blocklist or allowlist first")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Handle pending navigation from other views (e.g., BlocklistDetailView)
    private func handlePendingNavigation() {
        if let pending = viewModel.pendingScheduleToEdit {
            Task { @MainActor in
                viewModel.selectedScheduleId = (blocklistId: pending.blocklist.id, triggerId: pending.trigger.id)
                viewModel.pendingScheduleToEdit = nil
            }
        }
    }

    private func createNewSchedule(for blocklist: BlocklistConfig) {
        // Create a default schedule (9am-5pm weekdays)
        let defaultWindow = ScheduleBasedTrigger.ScheduleWindow(
            startHour: 9,
            startMinute: 0,
            endHour: 17,
            endMinute: 0,
            weekdays: ScheduleBasedTrigger.ScheduleWindow.weekdaysOnly
        )
        let schedule = ScheduleBasedTrigger(windows: [defaultWindow])
        let triggerId = viewModel.addSchedule(to: blocklist, schedule: schedule)
        viewModel.selectedScheduleId = (blocklistId: blocklist.id, triggerId: triggerId)
    }
}

// MARK: - Schedule Row View

struct ScheduleRowView: View {
    let trigger: TriggerConfig
    let blocklist: BlocklistConfig
    let viewModel: WillpowerViewModel

    /// Check if this specific schedule's time window is currently active
    var isActive: Bool {
        let evaluator = TriggerEvaluator()
        let result = evaluator.evaluateTrigger(trigger, visitRecords: [])
        return result.isActive
    }

    var body: some View {
        HStack {
            Image(systemName: isActive ? "clock.badge.checkmark.fill" : "calendar.badge.clock")
                .foregroundStyle(isActive ? Color.green : (trigger.isEnabled ? Color.accentColor : Color.gray))
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
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ScheduleWindow Extensions

extension ScheduleBasedTrigger.ScheduleWindow {
    var timeRangeDescription: String {
        func format12Hour(_ hour: Int, _ minute: Int) -> String {
            let isAM = hour < 12
            var hour12 = hour % 12
            if hour12 == 0 { hour12 = 12 }
            let period = isAM ? "AM" : "PM"
            if minute == 0 {
                return "\(hour12) \(period)"
            } else {
                return "\(hour12):\(String(format: "%02d", minute)) \(period)"
            }
        }
        let startTime = format12Hour(startHour, startMinute)
        let endTime = format12Hour(endHour, endMinute)
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
