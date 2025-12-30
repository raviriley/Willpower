//
//  TimeRemainingView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import Combine

struct TimeRemainingView: View {
    let expiresAt: Date

    @State private var timeRemaining: TimeInterval = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedTime)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(timeRemaining < 300 ? .red : .primary)
            .onReceive(timer) { _ in
                timeRemaining = max(0, expiresAt.timeIntervalSinceNow)
            }
            .onAppear {
                timeRemaining = max(0, expiresAt.timeIntervalSinceNow)
            }
    }

    private var formattedTime: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        TimeRemainingView(expiresAt: Date().addingTimeInterval(3661))
        TimeRemainingView(expiresAt: Date().addingTimeInterval(125))
        TimeRemainingView(expiresAt: Date().addingTimeInterval(59))
    }
    .padding()
}
