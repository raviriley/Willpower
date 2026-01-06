//
//  DaemonSetupView.swift
//  Willpower
//
//  Setup sheet that guides user through daemon registration
//

import SwiftUI
import ServiceManagement

struct DaemonSetupView: View {
    @Bindable var daemonManager: DaemonManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            // Title
            Text("Install Background Helper")
                .font(.title)
                .fontWeight(.semibold)

            // Description
            Text("Willpower needs to run in the background to block websites.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            // Status indicator
            DaemonStatusIndicatorView(
                status: daemonManager.status,
                statusDescription: daemonManager.statusDescription
            )

            // Error message
            if let error = daemonManager.lastError {
                DaemonErrorMessageView(error: error)
            }

            // Action buttons based on status
            actionButtons

            // Help text
            if daemonManager.needsApproval {
                DaemonApprovalInstructionsView(maxWidth: .infinity)
            }
        }
        .padding(32)
        .frame(width: 450, height: 500)
        .onAppear {
            daemonManager.refreshStatus()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            if daemonManager.needsInstallation {
                Button("Install Background Helper") {
                    daemonManager.register()
                }
                .buttonStyle(.borderedProminent)
            } else if daemonManager.needsApproval {
                Button("Open System Settings") {
                    daemonManager.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Status") {
                    daemonManager.refreshStatus()
                }
                .buttonStyle(.bordered)
            } else if daemonManager.isEnabled {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview {
    DaemonSetupView(daemonManager: DaemonManager())
}
