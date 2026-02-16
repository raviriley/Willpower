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

    // Time window configuration (stored in 24-hour format internally)
    @State private var startHour: Int = 9
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 17
    @State private var endMinute: Int = 0
    @State private var selectedWeekdays: Set<Int> = ScheduleBasedTrigger.ScheduleWindow.weekdaysOnly

    // 12-hour display state
    @State private var startDisplayHour: Int = 9
    @State private var startIsAM: Bool = true
    @State private var endDisplayHour: Int = 5
    @State private var endIsAM: Bool = false

    @State private var isShowingDeleteConfirmation = false

    // MARK: - 12/24 Hour Conversion Helpers

    private func to12Hour(_ hour24: Int) -> (hour: Int, isAM: Bool) {
        let isAM = hour24 < 12
        var hour12 = hour24 % 12
        if hour12 == 0 { hour12 = 12 }
        return (hour12, isAM)
    }

    private func to24Hour(_ hour12: Int, isAM: Bool) -> Int {
        if isAM {
            return hour12 == 12 ? 0 : hour12
        } else {
            return hour12 == 12 ? 12 : hour12 + 12
        }
    }

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
                    Section(schedule.blocklist.mode == .allow ? "Allowlist" : "Blocklist") {
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
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                            GridRow {
                                // Start time
                                HStack(spacing: 4) {
                                    Picker("Hour", selection: $startDisplayHour) {
                                        ForEach(1...12, id: \.self) {
                                            Text("\($0)").tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 50)

                                    Text(":")
                                        .foregroundStyle(.secondary)

                                    Picker("Minute", selection: $startMinute) {
                                        ForEach([0, 15, 30, 45], id: \.self) {
                                            Text(String(format: "%02d", $0)).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 50)

                                    Picker("AM/PM", selection: $startIsAM) {
                                        Text("AM").tag(true)
                                        Text("PM").tag(false)
                                    }
                                    .labelsHidden()
                                    .frame(width: 55)
                                }

                                // Arrow
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                    .font(.title3)

                                // End time
                                HStack(spacing: 4) {
                                    Picker("Hour", selection: $endDisplayHour) {
                                        ForEach(1...12, id: \.self) {
                                            Text("\($0)").tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 50)

                                    Text(":")
                                        .foregroundStyle(.secondary)

                                    Picker("Minute", selection: $endMinute) {
                                        ForEach([0, 15, 30, 45], id: \.self) {
                                            Text(String(format: "%02d", $0)).tag($0)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 50)

                                    Picker("AM/PM", selection: $endIsAM) {
                                        Text("AM").tag(true)
                                        Text("PM").tag(false)
                                    }
                                    .labelsHidden()
                                    .frame(width: 55)
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

                        Text("The \(schedule.blocklist.mode == .allow ? "allowlist" : "blocklist") will automatically activate during this time window on the selected days.")
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
                .onChange(of: startDisplayHour) { _, newValue in
                    startHour = to24Hour(newValue, isAM: startIsAM)
                    saveIfValid()
                }
                .onChange(of: startIsAM) { _, newValue in
                    startHour = to24Hour(startDisplayHour, isAM: newValue)
                    saveIfValid()
                }
                .onChange(of: startMinute) { _, _ in saveIfValid() }
                .onChange(of: endDisplayHour) { _, newValue in
                    endHour = to24Hour(newValue, isAM: endIsAM)
                    saveIfValid()
                }
                .onChange(of: endIsAM) { _, newValue in
                    endHour = to24Hour(endDisplayHour, isAM: newValue)
                    saveIfValid()
                }
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
            // Load 24-hour values
            startHour = window.startHour
            startMinute = window.startMinute
            endHour = window.endHour
            endMinute = window.endMinute
            selectedWeekdays = window.weekdays

            // Convert to 12-hour display
            let start12 = to12Hour(window.startHour)
            startDisplayHour = start12.hour
            startIsAM = start12.isAM

            let end12 = to12Hour(window.endHour)
            endDisplayHour = end12.hour
            endIsAM = end12.isAM
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
