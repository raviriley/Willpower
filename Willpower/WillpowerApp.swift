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
    @State private var showDaemonSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(daemonManager)
                .onAppear {
                    viewModel.startStateSync()
                    checkDaemonStatus()
                }
                .onDisappear {
                    viewModel.stopStateSync()
                }
                .sheet(isPresented: $showDaemonSetup) {
                    DaemonSetupView(daemonManager: daemonManager)
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 700)
    }

    private func checkDaemonStatus() {
        daemonManager.refreshStatus()

        // Show setup if daemon is not fully enabled
        if !daemonManager.isEnabled {
            showDaemonSetup = true
        }
    }
}
