//
//  AllowlistRowView.swift
//  Willpower
//
//  Created by Ravi Riley on 2/16/26.
//

import SwiftUI
import WillpowerKit

struct AllowlistRowView: View {
    let allowlist: BlocklistConfig
    let isActive: Bool
    let isLocked: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(allowlist.name)
                    .font(.headline)

                Text("\(allowlist.domains.count) domain\(allowlist.domains.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Circle()
                    .fill(isLocked ? .green : .mint)
                    .frame(width: 10, height: 10)
                    .help(isLocked ? "Locked - cannot be deactivated" : "Active")
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        AllowlistRowView(
            allowlist: BlocklistConfig(name: "Work Focus", domains: ["google.com", "github.com"], mode: .allow),
            isActive: false,
            isLocked: false
        )

        AllowlistRowView(
            allowlist: BlocklistConfig(name: "Study Mode", domains: ["wikipedia.org"], mode: .allow),
            isActive: true,
            isLocked: true
        )
    }
    .padding()
}
