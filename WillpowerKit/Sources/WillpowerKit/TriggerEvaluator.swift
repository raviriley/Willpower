//
//  TriggerEvaluator.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation

/// Evaluates trigger conditions for blocklists
public struct TriggerEvaluator: Sendable {

    // MARK: - Types

    /// Result of evaluating a trigger or blocklist
    public enum EvaluationResult: Sendable, Equatable {
        /// Block should not be active
        case inactive
        /// Block should be active until date (nil = indefinite for schedule-based)
        case active(expiresAt: Date?)
        /// Waiting for visit count threshold
        case pendingVisitCount(current: Int, threshold: Int)
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Evaluate a blocklist's triggers and determine if it should be active
    /// - Parameters:
    ///   - blocklist: The blocklist configuration to evaluate
    ///   - activeBlock: Existing active block for this blocklist (if any)
    ///   - visitRecords: Current visit records for URL pattern tracking
    /// - Returns: Evaluation result indicating if block should be active
    public func evaluate(
        blocklist: BlocklistConfig,
        activeBlock: ActiveBlock?,
        visitRecords: [VisitRecord]
    ) -> EvaluationResult {
        // If there's an existing locked block that hasn't expired, keep it active
        if let block = activeBlock, block.isLocked && !block.isExpired {
            return .active(expiresAt: block.expiresAt)
        }

        // If blocklist is not marked active and no locked block, it's inactive
        guard blocklist.isActive else {
            return .inactive
        }

        // Check each enabled trigger
        for trigger in blocklist.triggers where trigger.isEnabled {
            let result = evaluateTrigger(trigger, visitRecords: visitRecords)

            switch result {
            case .active:
                return result
            case .pendingVisitCount:
                // Return pending state for UI feedback, but continue checking other triggers
                return result
            case .inactive:
                continue
            }
        }

        // If blocklist is active but no triggers match, check if it's manually activated
        if let block = activeBlock, !block.isExpired {
            return .active(expiresAt: block.expiresAt)
        }

        return .inactive
    }

    /// Evaluate a single trigger
    /// - Parameters:
    ///   - trigger: The trigger configuration to evaluate
    ///   - visitRecords: Current visit records for visit-count triggers
    /// - Returns: Evaluation result
    public func evaluateTrigger(
        _ trigger: TriggerConfig,
        visitRecords: [VisitRecord]
    ) -> EvaluationResult {
        guard trigger.isEnabled else {
            return .inactive
        }

        switch trigger.type {
        case .timeBased:
            return evaluateTimeBased(trigger.timeBased)

        case .scheduleBased:
            return evaluateScheduleBased(trigger.scheduleBased)

        case .visitCount:
            return evaluateVisitCount(trigger.visitCount, visitRecords: visitRecords)
        }
    }

    // MARK: - Time-Based Evaluation

    private func evaluateTimeBased(_ config: TimeBasedTrigger?) -> EvaluationResult {
        guard let config else { return .inactive }

        let now = Date()

        // Check absolute end time
        if let endTime = config.endTime {
            if now < endTime {
                return .active(expiresAt: endTime)
            } else {
                return .inactive
            }
        }

        // Duration-based requires knowing when block was activated
        // This is typically handled by ActiveBlock.expiresAt when the block is created
        // If we only have duration without an active block, we can't evaluate it here
        return .inactive
    }

    // MARK: - Schedule-Based Evaluation

    private func evaluateScheduleBased(_ config: ScheduleBasedTrigger?) -> EvaluationResult {
        guard let config else { return .inactive }

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentMinutes = hour * 60 + minute

        // Yesterday's weekday (Sunday=1 wraps to Saturday=7)
        let yesterday = weekday == 1 ? 7 : weekday - 1

        for window in config.windows {
            let windowStart = window.startHour * 60 + window.startMinute
            let windowEnd = window.endHour * 60 + window.endMinute
            let isOvernightWindow = windowStart > windowEnd

            if isOvernightWindow {
                // Overnight window (e.g., 22:00 - 06:00)
                // Check both evening portion (today) and morning portion (yesterday's overnight)
                let inEveningPortion = window.weekdays.contains(weekday) && currentMinutes >= windowStart
                let inMorningPortion = window.weekdays.contains(yesterday) && currentMinutes < windowEnd

                if inEveningPortion || inMorningPortion {
                    var expiresAt = calculateEndTime(
                        hour: window.endHour,
                        minute: window.endMinute,
                        from: now
                    )

                    // If we're in the evening portion (after start), end time is tomorrow
                    if inEveningPortion {
                        expiresAt = calendar.date(byAdding: .day, value: 1, to: expiresAt) ?? expiresAt
                    }
                    // If we're in morning portion, end time is today (already correct)

                    return .active(expiresAt: expiresAt)
                }
            } else {
                // Normal window (e.g., 09:00 - 17:00)
                guard window.weekdays.contains(weekday) else { continue }

                if currentMinutes >= windowStart && currentMinutes < windowEnd {
                    let expiresAt = calculateEndTime(
                        hour: window.endHour,
                        minute: window.endMinute,
                        from: now
                    )
                    return .active(expiresAt: expiresAt)
                }
            }
        }

        return .inactive
    }

    private func calculateEndTime(hour: Int, minute: Int, from date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    // MARK: - Visit Count Evaluation

    private func evaluateVisitCount(
        _ config: VisitCountTrigger?,
        visitRecords: [VisitRecord]
    ) -> EvaluationResult {
        guard let config else { return .inactive }

        // Sum visits across all monitored patterns
        var totalVisits = 0

        for pattern in config.urlPatterns {
            if let record = visitRecords.first(where: { $0.patternId == pattern.id }) {
                totalVisits += record.visitCount
            }
        }

        if totalVisits >= config.maxVisits {
            let expiresAt = Date().addingTimeInterval(TimeInterval(config.blockDurationSeconds))
            return .active(expiresAt: expiresAt)
        }

        return .pendingVisitCount(current: totalVisits, threshold: config.maxVisits)
    }

    // MARK: - Utility Methods

    /// Check if any trigger in a blocklist is currently active
    public func hasActiveTrigger(
        blocklist: BlocklistConfig,
        visitRecords: [VisitRecord]
    ) -> Bool {
        for trigger in blocklist.triggers where trigger.isEnabled {
            let result = evaluateTrigger(trigger, visitRecords: visitRecords)
            if case .active = result {
                return true
            }
        }
        return false
    }

    /// Get the next schedule window start time for a blocklist
    public func nextScheduleStart(for blocklist: BlocklistConfig) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        var nextStart: Date?

        for trigger in blocklist.triggers where trigger.type == .scheduleBased {
            guard let scheduleConfig = trigger.scheduleBased else { continue }

            for window in scheduleConfig.windows {
                // Check next 7 days
                for dayOffset in 0..<7 {
                    guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
                        continue
                    }

                    let weekday = calendar.component(.weekday, from: checkDate)
                    guard window.weekdays.contains(weekday) else { continue }

                    var components = calendar.dateComponents([.year, .month, .day], from: checkDate)
                    components.hour = window.startHour
                    components.minute = window.startMinute

                    guard let windowStart = calendar.date(from: components),
                          windowStart > now else {
                        continue
                    }

                    if nextStart == nil || windowStart < nextStart! {
                        nextStart = windowStart
                    }
                }
            }
        }

        return nextStart
    }

    /// Calculate when a time-based block would expire if activated now
    public func calculateExpiration(for trigger: TriggerConfig) -> Date? {
        guard trigger.type == .timeBased,
              let timeBased = trigger.timeBased else {
            return nil
        }

        if let endTime = timeBased.endTime {
            return endTime
        }

        if let duration = timeBased.durationSeconds {
            return Date().addingTimeInterval(TimeInterval(duration))
        }

        return nil
    }
}

// MARK: - Evaluation Result Extensions

extension TriggerEvaluator.EvaluationResult {
    /// Whether this result indicates the block should be active
    public var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }

    /// Get expiration date if active
    public var expiresAt: Date? {
        if case .active(let date) = self {
            return date
        }
        return nil
    }

    /// Get visit count info if pending
    public var visitCountInfo: (current: Int, threshold: Int)? {
        if case .pendingVisitCount(let current, let threshold) = self {
            return (current, threshold)
        }
        return nil
    }
}
