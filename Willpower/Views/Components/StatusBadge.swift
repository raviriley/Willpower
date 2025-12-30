//
//  StatusBadge.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 10) {
        StatusBadge(text: "LOCKED", color: .red)
        StatusBadge(text: "ACTIVE", color: .orange)
        StatusBadge(text: "SCHEDULED", color: .blue)
        StatusBadge(text: "EXPIRED", color: .gray)
    }
    .padding()
}
