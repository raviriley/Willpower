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

// MARK: - Time Formatting

/// Format an hour/minute pair respecting the user's time format preference.
/// - Returns: e.g. "14:05" (24h) or "2:05 PM" (12h)
func formatTime(hour: Int, minute: Int, use24Hour: Bool) -> String {
    if use24Hour {
        return String(format: "%02d:%02d", hour, minute)
    } else {
        let isAM = hour < 12
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", hour12, minute, isAM ? "AM" : "PM")
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
