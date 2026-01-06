//
//  DaemonStatusIndicator.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI

struct DaemonStatusIndicator: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? .green : .red)
                .frame(width: 8, height: 8)

            Text(isRunning ? "Running" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(isRunning
            ? "Willpower daemon is active and monitoring"
            : "Daemon is not running - blocks may not be enforced"
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        DaemonStatusIndicator(isRunning: true)
        DaemonStatusIndicator(isRunning: false)
    }
    .padding()
}
