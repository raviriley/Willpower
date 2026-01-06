//
//  FormatUtilities.swift
//  Willpower
//
//  Shared formatting utilities used across multiple views.
//

import SwiftUI

// MARK: - Duration Formatting

/// Format a duration in seconds to a human-readable string
/// Examples: "1h 30m", "2 hours", "45 minutes"
func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60

    if hours > 0 && minutes > 0 {
        return "\(hours)h \(minutes)m"
    } else if hours > 0 {
        return "\(hours) hour\(hours == 1 ? "" : "s")"
    } else {
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

// MARK: - Visit Count Color

/// Get a color based on the ratio of current visits to max visits
/// - Parameters:
///   - current: Current visit count
///   - max: Maximum allowed visits
/// - Returns: Color indicating severity (green -> yellow -> orange -> red)
func visitCountColor(current: Int, max: Int) -> Color {
    let ratio = Double(current) / Double(max)
    if ratio >= 1.0 {
        return .red
    } else if ratio >= 0.7 {
        return .orange
    } else if ratio >= 0.4 {
        return .yellow
    } else {
        return .green
    }
}
