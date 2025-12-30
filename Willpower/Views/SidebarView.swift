//
//  SidebarView.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedCategory: SidebarCategory

    var body: some View {
        List(SidebarCategory.allCases, selection: $selectedCategory) { category in
            Label(category.rawValue, systemImage: category.icon)
                .tag(category)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }
}

#Preview {
    SidebarView(selectedCategory: .constant(.status))
}
