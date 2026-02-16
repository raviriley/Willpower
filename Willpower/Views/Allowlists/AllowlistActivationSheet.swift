//
//  AllowlistActivationSheet.swift
//  Willpower
//
//  Created by Ravi Riley on 2/16/26.
//

import SwiftUI
import WillpowerKit

struct AllowlistActivationSheet: View {
    @Bindable var viewModel: WillpowerViewModel
    let allowlistId: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var durationMinutes: Double = 60
    @State private var isLocked: Bool = true

    /// Get the current allow list from viewModel (always fresh)
    var allowlist: BlocklistConfig? {
        viewModel.blocklists.first { $0.id == allowlistId }
    }

    // Slider range: 1 minute to 24 hours (1440 minutes)
    private let minDuration: Double = 1
    private let maxDuration: Double = 1440

    var formattedDuration: String {
        let totalMinutes = Int(durationMinutes)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else if minutes == 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }

    var body: some View {
        Group {
            if let allowlist {
                activationContent(allowlist: allowlist)
            } else {
                ContentUnavailableView(
                    "Allow List Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This allow list may have been deleted")
                )
            }
        }
        .frame(width: 450, height: 550)
    }

    @ViewBuilder
    private func activationContent(allowlist: BlocklistConfig) -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)

                Text("Activate \(allowlist.name)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(allowlist.domains.count) domain\(allowlist.domains.count == 1 ? "" : "s") will be allowed")
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Duration Display
            Text(formattedDuration)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: durationMinutes)

            // Duration Slider
            VStack(spacing: 12) {
                Slider(value: $durationMinutes, in: minDuration...maxDuration) {
                    Text("Duration")
                } minimumValueLabel: {
                    Text("1m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("24h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(.green)

                // Quick presets
                HStack(spacing: 8) {
                    ForEach([15, 30, 60, 120, 240, 480], id: \.self) { minutes in
                        Button(presetLabel(for: minutes)) {
                            withAnimation(.snappy) {
                                durationMinutes = Double(minutes)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Int(durationMinutes) == minutes ? .green : .secondary)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal)

            // Lock Toggle
            GroupBox {
                Toggle(isOn: $isLocked) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .foregroundStyle(isLocked ? .green : .secondary)
                            Text("Lock Allow List")
                                .font(.headline)
                        }
                        Text(isLocked ? "Cannot be disabled until time expires" : "Can be disabled at any time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .backgroundStyle(isLocked ? Color.green.opacity(0.1) : Color.clear)

            if isLocked {
                Label("This allow list cannot be cancelled once started", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange.opacity(0.8))
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.bordered)

                Button("Start Allow List") {
                    activateAndDismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(allowlist.domains.isEmpty)
            }
        }
        .padding(24)
    }

    private func presetLabel(for minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }

    private func activateAndDismiss() {
        guard let allowlist, !allowlist.domains.isEmpty else { return }
        let durationSeconds = Int(durationMinutes * 60)
        viewModel.activateBlocklist(allowlist, durationSeconds: durationSeconds, isLocked: isLocked)
        dismiss()
    }
}

#Preview {
    let viewModel = WillpowerViewModel()
    let allowlist = BlocklistConfig(
        name: "Work Focus",
        domains: ["google.com", "github.com", "stackoverflow.com"],
        mode: .allow
    )
    viewModel.blocklists.append(allowlist)

    return AllowlistActivationSheet(
        viewModel: viewModel,
        allowlistId: allowlist.id
    )
}
