//
//  OnboardingView.swift
//  Willpower
//
//  First-launch onboarding flow guiding users through setup
//

import SwiftUI
import ServiceManagement
import WillpowerKit

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case daemonSetup = 1
    case createBlocklist = 2

    var title: String {
        switch self {
        case .welcome: return "Welcome to Willpower"
        case .daemonSetup: return "Install Background Helper"
        case .createBlocklist: return "Create Your First Blocklist"
        }
    }
}

struct OnboardingView: View {
    @Bindable var viewModel: WillpowerViewModel
    @Bindable var daemonManager: DaemonManager
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(onContinue: { currentStep = .daemonSetup })
                case .daemonSetup:
                    DaemonSetupStepView(
                        daemonManager: daemonManager,
                        onContinue: { currentStep = .createBlocklist }
                    )
                case .createBlocklist:
                    CreateBlocklistStepView(
                        viewModel: viewModel,
                        onComplete: onComplete
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 550, height: 600)
        .background(.background)
    }

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    // Step circle
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 28, height: 28)

                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(step == currentStep ? .white : .secondary)
                        }
                    }

                    // Step label (only for current step)
                    if step == currentStep {
                        Text(step.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    // Connector line
                    if step != OnboardingStep.allCases.last {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 40, height: 2)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func stepColor(for step: OnboardingStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .blue
        } else {
            return .secondary.opacity(0.3)
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon placeholder
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 16) {
                Text("Take Control of Your Attention")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Willpower blocks distracting websites so you can focus on what matters.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Features
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "list.bullet.rectangle", title: "Blocklists", description: "Group distracting sites together")
                FeatureRow(icon: "calendar.badge.clock", title: "Schedules", description: "Automatic blocking during certain hours")
                FeatureRow(icon: "eye.trianglebadge.exclamationmark", title: "Visit Limits", description: "Block sites after too many visits")
                FeatureRow(icon: "lock.fill", title: "Locked Blocks", description: "Can't be bypassed until time's up, even if you delete the app")
            }
            .padding(.horizontal, 48)

            Spacer()

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Daemon Setup Step

struct DaemonSetupStepView: View {
    @Bindable var daemonManager: DaemonManager
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(daemonManager.isEnabled ? .green : .blue)

            // Title
            Text(daemonManager.isEnabled ? "Background Helper Installed" : "Install Background Helper")
                .font(.title2)
                .fontWeight(.semibold)

            // Description
            Text("Willpower needs to run in the background to block websites.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 48)

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

            // Help text for approval
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
                .frame(maxWidth: 350, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                if daemonManager.needsInstallation {
                    Button("Install Background Helper") {
                        daemonManager.register()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else if daemonManager.needsApproval {
                    Button("Open System Settings") {
                        daemonManager.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Refresh Status") {
                        daemonManager.refreshStatus()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else if daemonManager.isEnabled {
                    Button("Continue") {
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(.bottom, 32)
        }
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
}

// MARK: - Create Blocklist Step

struct CreateBlocklistStepView: View {
    @Bindable var viewModel: WillpowerViewModel
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            // Title
            Text("Create Your First Blocklist")
                .font(.title)
                .fontWeight(.bold)

            // Description
            VStack(spacing: 12) {
                Text("You're all set! Time to create your first list of domains to block.")
                    .font(.body)
            }
            .padding(.horizontal, 48)

            Spacer()

            // Action button
            Button("Let's Go!") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
    }
}

#Preview {
    OnboardingView(
        viewModel: WillpowerViewModel(),
        daemonManager: DaemonManager(),
        onComplete: {}
    )
}
