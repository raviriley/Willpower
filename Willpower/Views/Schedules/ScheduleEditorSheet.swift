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

    @State private var windows: [ScheduleBasedTrigger.ScheduleWindow] = []
    @State private var isAddingWindow = false
    /// Original windows when editing (to track what's protected if active)
    @State private var originalWindows: [ScheduleBasedTrigger.ScheduleWindow] = []

    var isEditing: Bool { existingTrigger != nil }

    /// Check if this schedule has an active block right now
    var isScheduleActive: Bool {
        guard existingTrigger != nil else { return false }
        // Check if there's an active block for this blocklist with schedule reason
        return viewModel.activeBlocks.contains {
            $0.blocklistId == blocklist.id &&
            $0.reason == .scheduleBasedTrigger &&
            !$0.isExpired
        }
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

                Section("Schedule Windows") {
                    ForEach(windows) { window in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(window.timeRangeDescription)
                                    .font(.headline)
                                Text(window.weekdaysDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                windows.removeAll { $0.id == window.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button("Add Time Window") {
                        isAddingWindow = true
                    }
                }

                Section {
                    Text("The blocklist will automatically activate during these time windows.")
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
                    .disabled(windows.isEmpty)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .sheet(isPresented: $isAddingWindow) {
            TimeWindowEditorSheet { window in
                windows.append(window)
            }
        }
        .onAppear {
            if let trigger = existingTrigger, let schedule = trigger.scheduleBased {
                windows = schedule.windows
                originalWindows = schedule.windows
            }
        }
    }

    private func save() {
        let schedule = ScheduleBasedTrigger(windows: windows)

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

// MARK: - Time Window Editor Sheet

struct TimeWindowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var startHour: Int = 9
    @State private var startMinute: Int = 0
    @State private var endHour: Int = 17
    @State private var endMinute: Int = 0
    @State private var selectedWeekdays: Set<Int> = ScheduleBasedTrigger.ScheduleWindow.weekdaysOnly

    var onSave: (ScheduleBasedTrigger.ScheduleWindow) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Add Schedule Window")
                .font(.title2)
                .fontWeight(.semibold)

            // Time Pickers
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("Start Time")
                        .font(.headline)
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

                VStack(spacing: 8) {
                    Text("End Time")
                        .font(.headline)
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

            // Weekday Picker
            WeekdayPicker(selectedDays: $selectedWeekdays)

            Spacer()

            // Actions
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.bordered)

                Button("Add") {
                    let window = ScheduleBasedTrigger.ScheduleWindow(
                        startHour: startHour,
                        startMinute: startMinute,
                        endHour: endHour,
                        endMinute: endMinute,
                        weekdays: selectedWeekdays
                    )
                    onSave(window)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(selectedWeekdays.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 380)
    }
}

#Preview {
    ScheduleEditorSheet(
        viewModel: WillpowerViewModel(),
        blocklist: BlocklistConfig(name: "Social Media", domains: ["twitter.com"])
    )
}
