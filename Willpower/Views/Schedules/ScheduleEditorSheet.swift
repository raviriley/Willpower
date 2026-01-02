//
//  ScheduleEditorSheet.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct ScheduleEditorSheet: View {
    @Bindable var viewModel: WillpowerViewModel
    let blocklist: BlocklistConfig
    /// Existing trigger to edit (nil for new schedule)
    let existingTrigger: TriggerConfig?

    @Environment(\.dismiss) private var dismiss

    // Time window configuration (inline, single window per schedule)
    @State private var startHour: Int = 9
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 17
    @State private var endMinute: Int = 0
    @State private var selectedWeekdays: Set<Int> = ScheduleBasedTrigger.ScheduleWindow.weekdaysOnly

    var isEditing: Bool { existingTrigger != nil }

    /// Check if this schedule has an active block right now
    var isScheduleActive: Bool {
        guard let trigger = existingTrigger else { return false }
        let evaluator = TriggerEvaluator()
        let result = evaluator.evaluateTrigger(trigger, visitRecords: [])
        return result.isActive
    }

    /// Formatted time range for display
    var timeRangeDescription: String {
        let start = String(format: "%02d:%02d", startHour, startMinute)
        let end = String(format: "%02d:%02d", endHour, endMinute)
        return "\(start) - \(end)"
    }

    /// Check if this is an overnight schedule
    var isOvernightSchedule: Bool {
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        return startMinutes > endMinutes
    }

    init(viewModel: WillpowerViewModel, blocklist: BlocklistConfig, existingTrigger: TriggerConfig? = nil) {
        self.viewModel = viewModel
        self.blocklist = blocklist
        self.existingTrigger = existingTrigger
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Blocklist") {
                    LabeledContent("Name", value: blocklist.name)
                    LabeledContent("Domains", value: "\(blocklist.domains.count)")
                }

                // Active schedule warning
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
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Picker("Hour", selection: $startHour) {
                                    ForEach(0..<24, id: \.self) {
                                        Text(String(format: "%02d", $0)).tag($0)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 60)

                                Text(":")

                                Picker("Minute", selection: $startMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) {
                                        Text(String(format: "%02d", $0)).tag($0)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 60)
                            }
                        }

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("End")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Picker("Hour", selection: $endHour) {
                                    ForEach(0..<24, id: \.self) {
                                        Text(String(format: "%02d", $0)).tag($0)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 60)

                                Text(":")

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
                    .padding(.vertical, 4)

                    if isOvernightSchedule {
                        Label("Overnight schedule (ends next day)", systemImage: "moon.stars")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Days Section
                Section("Days") {
                    WeekdayPicker(selectedDays: $selectedWeekdays)
                        .padding(.vertical, 4)
                }

                Section {
                    Text("The blocklist will automatically activate during this time window on the selected days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Schedule" : "New Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        save()
                    }
                    .disabled(selectedWeekdays.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 350)
        .onAppear {
            if let trigger = existingTrigger,
               let schedule = trigger.scheduleBased,
               let window = schedule.windows.first {
                startHour = window.startHour
                startMinute = window.startMinute
                endHour = window.endHour
                endMinute = window.endMinute
                selectedWeekdays = window.weekdays
            }
        }
    }

    private func save() {
        let window = ScheduleBasedTrigger.ScheduleWindow(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            weekdays: selectedWeekdays
        )
        let schedule = ScheduleBasedTrigger(windows: [window])

        if let existingTrigger {
            // Update existing schedule
            viewModel.updateSchedule(triggerId: existingTrigger.id, in: blocklist, newSchedule: schedule)
        } else {
            // Create new schedule
            viewModel.addSchedule(to: blocklist, schedule: schedule)
        }
        dismiss()
    }
}

#Preview {
    ScheduleEditorSheet(
        viewModel: WillpowerViewModel(),
        blocklist: BlocklistConfig(name: "Social Media", domains: ["twitter.com"])
    )
}
