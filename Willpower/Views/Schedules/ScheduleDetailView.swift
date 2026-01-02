//
//  ScheduleDetailView.swift
//  Willpower
//
//  Created by Ravi Riley on 1/2/26.
//

import SwiftUI
import WillpowerKit

struct ScheduleDetailView: View {
    @Bindable var viewModel: WillpowerViewModel

    // Time window configuration
    @State private var startHour: Int = 9
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 17
    @State private var endMinute: Int = 0
    @State private var selectedWeekdays: Set<Int> = ScheduleBasedTrigger.ScheduleWindow.weekdaysOnly

    @State private var isShowingDeleteConfirmation = false

    /// Get the current schedule from viewModel (always fresh)
    var schedule: (blocklist: BlocklistConfig, trigger: TriggerConfig)? {
        viewModel.selectedSchedule
    }

    /// Check if this schedule's time window is currently active
    var isScheduleActive: Bool {
        guard let trigger = schedule?.trigger else { return false }
        let evaluator = TriggerEvaluator()
        let result = evaluator.evaluateTrigger(trigger, visitRecords: [])
        return result.isActive
    }

    /// Check if this is an overnight schedule
    var isOvernightSchedule: Bool {
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        return startMinutes > endMinutes
    }

    var body: some View {
        Group {
            if let schedule {
                Form {
                    Section("Blocklist") {
                        LabeledContent("Name", value: schedule.blocklist.name)
                        LabeledContent("Domains", value: "\(schedule.blocklist.domains.count)")
                    }

                    // Active schedule indicator
                    if isScheduleActive {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.badge.checkmark.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Schedule is Currently Active")
                                        .font(.headline)
                                    Text("Changes will take effect after the current window ends.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Time Range Section
                    Section("Time Range") {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                            GridRow {
                                // Start time
                                HStack(spacing: 4) {
                                    Picker("Hour", selection: $startHour) {
                                        ForEach(0..<24, id: \.self) {
                                            Text(String(format: "%02d", $0)).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 60)

                                    Text(":")
                                        .foregroundStyle(.secondary)

                                    Picker("Minute", selection: $startMinute) {
                                        ForEach([0, 15, 30, 45], id: \.self) {
                                            Text(String(format: "%02d", $0)).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 60)
                                }

                                // Arrow
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.title3)

                                // End time
                                HStack(spacing: 4) {
                                    Picker("Hour", selection: $endHour) {
                                        ForEach(0..<24, id: \.self) {
                                            Text(String(format: "%02d", $0)).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 60)

                                    Text(":")
                                        .foregroundStyle(.secondary)

                                    Picker("Minute", selection: $endMinute) {
                                        ForEach([0, 15, 30, 45], id: \.self) {
                                            Text(String(format: "%02d", $0)).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 60)
                                }
                            }
                        }

                        if isOvernightSchedule {
                            Label("Overnight schedule (ends next day)", systemImage: "moon.stars")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    // Days Section
                    Section("Days") {
                        WeekdayPicker(selectedDays: $selectedWeekdays)

                        Text("The blocklist will automatically activate during this time window on the selected days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Delete Section
                    Section {
                        Button("Delete Schedule", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Schedule")
                .onChange(of: startHour) { _, _ in saveIfValid() }
                .onChange(of: startMinute) { _, _ in saveIfValid() }
                .onChange(of: endHour) { _, _ in saveIfValid() }
                .onChange(of: endMinute) { _, _ in saveIfValid() }
                .onChange(of: selectedWeekdays) { _, _ in saveIfValid() }
                .alert("Delete Schedule?", isPresented: $isShowingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        deleteSchedule()
                    }
                } message: {
                    Text("Are you sure you want to delete this schedule? This cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "Select a Schedule",
                    systemImage: "calendar.badge.clock",
                    description: Text("Choose a schedule to view or edit")
                )
            }
        }
        .onChange(of: viewModel.selectedScheduleId?.triggerId) { _, _ in
            loadScheduleData()
        }
        .onAppear {
            loadScheduleData()
        }
    }

    private func loadScheduleData() {
        if let trigger = schedule?.trigger,
           let scheduleConfig = trigger.scheduleBased,
           let window = scheduleConfig.windows.first {
            startHour = window.startHour
            startMinute = window.startMinute
            endHour = window.endHour
            endMinute = window.endMinute
            selectedWeekdays = window.weekdays
        }
    }

    private func saveIfValid() {
        guard let schedule else { return }
        // Only save if at least one weekday is selected
        guard !selectedWeekdays.isEmpty else { return }

        let window = ScheduleBasedTrigger.ScheduleWindow(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            weekdays: selectedWeekdays
        )
        let newSchedule = ScheduleBasedTrigger(windows: [window])

        viewModel.updateSchedule(
            triggerId: schedule.trigger.id,
            in: schedule.blocklist,
            newSchedule: newSchedule
        )
    }

    private func deleteSchedule() {
        guard let schedule else { return }
        viewModel.removeSchedule(triggerId: schedule.trigger.id, from: schedule.blocklist)
        viewModel.selectedScheduleId = nil
    }
}

#Preview {
    ScheduleDetailView(viewModel: WillpowerViewModel())
}
