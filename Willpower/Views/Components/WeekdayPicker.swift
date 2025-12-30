//
//  WeekdayPicker.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct WeekdayPicker: View {
    @Binding var selectedDays: Set<Int>

    private let days: [(Int, String)] = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]

    private let dayNames: [(Int, String)] = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Days")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(days, id: \.0) { day, label in
                    Button {
                        if selectedDays.contains(day) {
                            selectedDays.remove(day)
                        } else {
                            selectedDays.insert(day)
                        }
                    } label: {
                        Text(label)
                            .font(.system(.body, weight: .medium))
                            .frame(width: 36, height: 36)
                            .background(selectedDays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.2))
                            .foregroundStyle(selectedDays.contains(day) ? .white : .primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(dayNames.first { $0.0 == day }?.1 ?? "")
                }
            }

            // Presets
            HStack(spacing: 16) {
                Button("Weekdays") {
                    selectedDays = ScheduleBasedTrigger.ScheduleWindow.weekdaysOnly
                }
                Button("Weekends") {
                    selectedDays = ScheduleBasedTrigger.ScheduleWindow.weekendsOnly
                }
                Button("Every Day") {
                    selectedDays = ScheduleBasedTrigger.ScheduleWindow.everyday
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

#Preview {
    @Previewable @State var selectedDays: Set<Int> = [2, 3, 4, 5, 6]

    WeekdayPicker(selectedDays: $selectedDays)
        .padding()
}
