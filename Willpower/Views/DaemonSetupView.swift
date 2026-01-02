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
                .foregroundStyle(.blue)

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
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(daemonManager.statusDescription)
                    .font(.headline)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            // Error message
            if let error = daemonManager.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding()
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            // Action buttons based on status
            actionButtons

            // Help text
            if daemonManager.needsApproval {
                VStack(alignment: .leading, spacing: 12) {
                    Text("After clicking 'Open System Settings':")
                        .font(.callout)
                        .fontWeight(.medium)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("1.")
                                .fontWeight(.semibold)
                                .frame(width: 20, alignment: .trailing)
                            Text("Go to **General** > **Login Items**")
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("2.")
                                .fontWeight(.semibold)
                                .frame(width: 20, alignment: .trailing)
                            Text("Find **Willpower** under 'Allow in the Background'")
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("3.")
                                .fontWeight(.semibold)
                                .frame(width: 20, alignment: .trailing)
                            Text("Toggle it **ON**")
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Text("4.")
                                .fontWeight(.semibold)
                                .frame(width: 20, alignment: .trailing)
                            Text("Click **Refresh Status**")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(32)
        .frame(width: 450, height: 500)
        .onAppear {
            daemonManager.refreshStatus()
        }
    }

    private var statusColor: Color {
        switch daemonManager.status {
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
