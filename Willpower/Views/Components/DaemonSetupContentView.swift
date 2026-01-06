//
//  DaemonSetupContentView.swift
//  Willpower
//
//  Shared daemon setup UI components used by both DaemonSetupView and OnboardingView.
//

import SwiftUI
import ServiceManagement

// MARK: - Daemon Status Color

/// Get the status color for daemon registration status
func daemonStatusColor(for status: SMAppService.Status) -> Color {
    switch status {
    case .enabled:
        return .green
    case .requiresApproval:
        return .orange
    case .notRegistered, .notFound:
        return .red
    @unknown default:
        return .gray
    }
}

// MARK: - Status Indicator

/// Status indicator showing daemon registration status
struct DaemonStatusIndicatorView: View {
    let status: SMAppService.Status
    let statusDescription: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(daemonStatusColor(for: status))
                .frame(width: 10, height: 10)
            Text(statusDescription)
                .font(.headline)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Error Message

/// Error message display for daemon setup errors
struct DaemonErrorMessageView: View {
    let error: String

    var body: some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.callout)
            .padding()
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Approval Instructions

/// Instructions shown when daemon needs system settings approval
struct DaemonApprovalInstructionsView: View {
    var maxWidth: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("After clicking 'Open System Settings':")
                .font(.callout)
                .fontWeight(.medium)

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: 1, text: "Go to **General** > **Login Items**")
                instructionRow(number: 2, text: "Find **Willpower** under 'Allow in the Background'")
                instructionRow(number: 3, text: "Toggle it **ON**")
                instructionRow(number: 4, text: "Click **Refresh Status**")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }
}
