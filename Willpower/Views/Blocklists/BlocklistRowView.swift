//
//  BlocklistRowView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct BlocklistRowView: View {
    let blocklist: BlocklistConfig
    let isActive: Bool
    let isLocked: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(blocklist.name)
                    .font(.headline)

                Text("\(blocklist.domains.count) domain\(blocklist.domains.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Circle()
                    .fill(isLocked ? .red : .orange)
                    .frame(width: 10, height: 10)
                    .help(isLocked ? "Locked - cannot be deactivated" : "Active")
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        BlocklistRowView(
            blocklist: BlocklistConfig(name: "Social Media", domains: ["twitter.com", "facebook.com"]),
            isActive: false,
            isLocked: false
        )

        BlocklistRowView(
            blocklist: BlocklistConfig(name: "News Sites", domains: ["cnn.com"]),
            isActive: true,
            isLocked: false
        )

        BlocklistRowView(
            blocklist: BlocklistConfig(name: "Distractions", domains: ["youtube.com", "reddit.com", "tiktok.com"]),
            isActive: true,
            isLocked: true
        )
    }
    .padding()
}
