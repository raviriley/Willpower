//
//  ManualActivationSheet.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct ManualActivationSheet: View {
    @Bindable var viewModel: WillpowerViewModel
    let blocklistId: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var durationMinutes: Double = 60
    @State private var isLocked: Bool = true
    @State private var showingConfirmation: Bool = false

    /// Get the current blocklist from viewModel (always fresh)
    var blocklist: BlocklistConfig? {
        viewModel.blocklists.first { $0.id == blocklistId }
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
            if let blocklist {
                activationContent(blocklist: blocklist)
            } else {
                ContentUnavailableView(
                    "Blocklist Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This blocklist may have been deleted")
                )
            }
        }
        .frame(width: 450, height: 550)
    }

    @ViewBuilder
    private func activationContent(blocklist: BlocklistConfig) -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)

                Text("Activate \(blocklist.name)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(blocklist.domains.count) domain\(blocklist.domains.count == 1 ? "" : "s") will be blocked")
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

                // Quick presets
                HStack(spacing: 8) {
                    ForEach([15, 30, 60, 120, 240, 480], id: \.self) { minutes in
                        Button(presetLabel(for: minutes)) {
                            withAnimation(.snappy) {
                                durationMinutes = Double(minutes)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(Int(durationMinutes) == minutes ? .accentColor : .secondary)
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
                                .foregroundStyle(isLocked ? .red : .secondary)
                            Text("Lock Block")
                                .font(.headline)
                        }
                        Text("Cannot be disabled until time expires")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .backgroundStyle(isLocked ? Color.red.opacity(0.1) : Color.clear)

            if isLocked {
                Label("This block cannot be cancelled once started", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.bordered)

                Button("Start Block") {
                    if isLocked {
                        showingConfirmation = true
                    } else {
                        activateAndDismiss()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(isLocked ? .red : .accentColor)
            }
        }
        .padding(24)
        .confirmationDialog(
            "Start Locked Block?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start \(formattedDuration) Block", role: .destructive) {
                activateAndDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This block cannot be cancelled until it expires. \(blocklist.domains.count) domain(s) will be blocked for \(formattedDuration).")
        }
    }

    private func presetLabel(for minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        return "\(minutes / 60)h"
    }

    private func activateAndDismiss() {
        guard let blocklist else { return }
        let durationSeconds = Int(durationMinutes * 60)
        viewModel.activateBlocklist(blocklist, durationSeconds: durationSeconds, isLocked: isLocked)
        dismiss()
    }
}

#Preview {
    let viewModel = WillpowerViewModel()
    let blocklist = BlocklistConfig(
        name: "Social Media",
        domains: ["twitter.com", "facebook.com", "instagram.com"]
    )
    viewModel.blocklists.append(blocklist)

    return ManualActivationSheet(
        viewModel: viewModel,
        blocklistId: blocklist.id
    )
}
