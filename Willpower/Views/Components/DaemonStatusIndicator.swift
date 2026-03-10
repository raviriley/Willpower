//
//  DaemonStatusIndicator.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI

struct DaemonStatusIndicator: View {
    let isRunning: Bool
    var isUpdateAvailable: Bool = false
    var onUpdateTap: (() -> Void)? = nil

    private var color: Color {
        if !isRunning { return .red }
        if isUpdateAvailable { return .yellow }
        return .green
    }

    private var label: String {
        if !isRunning { return "Offline" }
        if isUpdateAvailable { return "Update Available" }
        return "Running"
    }

    private var tooltip: String {
        if !isRunning { return "Daemon is not running - blocks may not be enforced" }
        if isUpdateAvailable { return "A newer version of Willpower is available — click to update" }
        return "Willpower daemon is active and monitoring"
    }

    var body: some View {
        if isUpdateAvailable, let onUpdateTap {
            Button(action: onUpdateTap) {
                indicator
            }
            .buttonStyle(.plain)
        } else {
            indicator
        }
    }

    private var indicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(tooltip)
    }
}

#Preview {
    VStack(spacing: 20) {
        DaemonStatusIndicator(isRunning: true)
        DaemonStatusIndicator(isRunning: true, isUpdateAvailable: true)
        DaemonStatusIndicator(isRunning: false)
    }
    .padding()
}
