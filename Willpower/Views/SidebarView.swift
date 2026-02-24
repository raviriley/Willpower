//
//  SidebarView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: SidebarCategory
    var isDaemonRunning: Bool = false
    var isUpdateAvailable: Bool = false

    var body: some View {
        List(SidebarCategory.allCases, selection: $selectedCategory) { category in
            Label(category.rawValue, systemImage: category.icon)
                .tag(category)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                DaemonStatusIndicator(isRunning: isDaemonRunning, isUpdateAvailable: isUpdateAvailable)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }
}

#Preview {
    SidebarView(selectedCategory: .constant(.status), isDaemonRunning: true)
}
