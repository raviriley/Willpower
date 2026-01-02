//
//  WillpowerApp.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

@main
struct WillpowerApp: App {
    @State private var viewModel = WillpowerViewModel()
    @State private var daemonManager = DaemonManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var showDaemonSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(daemonManager)
                .onAppear {
                    viewModel.startStateSync()
                    daemonManager.refreshStatus()

                    if !hasCompletedOnboarding {
                        // First-time user: show full onboarding
                        showOnboarding = true
                    } else if !daemonManager.isEnabled {
                        // Returning user but daemon needs setup: show daemon setup only
                        showDaemonSetup = true
                    }
                }
                .onDisappear {
                    viewModel.stopStateSync()
                }
                // First-time onboarding (full flow)
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(
                        viewModel: viewModel,
                        daemonManager: daemonManager,
                        onComplete: {
                            hasCompletedOnboarding = true
                            showOnboarding = false
                        }
                    )
                    .interactiveDismissDisabled()
                }
                // Returning user daemon setup (just step 2)
                .sheet(isPresented: $showDaemonSetup) {
                    DaemonSetupView(daemonManager: daemonManager)
                        .interactiveDismissDisabled(!daemonManager.isEnabled)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
    }
}
