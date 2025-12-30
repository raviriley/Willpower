//
//  ActiveBlockRowView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct ActiveBlockRowView: View {
    let block: ActiveBlock
    let blocklist: BlocklistConfig?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(blocklist?.name ?? "Unknown Blocklist")
                    .font(.headline)

                Text("\(block.domains.count) domains blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(block.reason.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if block.isLocked {
                    StatusBadge(text: "LOCKED", color: .red)
                } else {
                    StatusBadge(text: "ACTIVE", color: .orange)
                }

                if let expiresAt = block.expiresAt {
                    TimeRemainingView(expiresAt: expiresAt)
                } else {
                    Text("Indefinite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - BlockReason Display Name

extension ActiveBlock.BlockReason {
    var displayName: String {
        switch self {
        case .manualActivation:
            return "Manual activation"
        case .timeBasedTrigger:
            return "Time-based trigger"
        case .scheduleBasedTrigger:
            return "Scheduled"
        case .visitCountTrigger:
            return "Visit threshold exceeded"
        }
    }
}

#Preview {
    VStack {
        ActiveBlockRowView(
            block: ActiveBlock(
                blocklistId: UUID(),
                domains: ["youtube.com", "twitter.com", "facebook.com"],
                expiresAt: Date().addingTimeInterval(3600),
                reason: .manualActivation,
                isLocked: true
            ),
            blocklist: BlocklistConfig(name: "Social Media", domains: ["youtube.com"])
        )

        Divider()

        ActiveBlockRowView(
            block: ActiveBlock(
                blocklistId: UUID(),
                domains: ["reddit.com"],
                expiresAt: Date().addingTimeInterval(120),
                reason: .visitCountTrigger,
                isLocked: true
            ),
            blocklist: BlocklistConfig(name: "Distractions", domains: ["reddit.com"])
        )
    }
    .padding()
}
