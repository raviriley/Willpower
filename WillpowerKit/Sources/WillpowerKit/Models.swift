//
//  Models.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation

// MARK: - Trigger Types

/// Defines how a blocklist can be triggered
public enum TriggerType: String, Codable, Sendable, CaseIterable {
    case timeBased      // Block for X hours or until specific time
    case scheduleBased  // Recurring schedule (e.g., 9am-5pm weekdays)
    case visitCount     // Block after N visits to URL patterns
}

// MARK: - Time-Based Trigger

/// Configuration for time-based triggers
public struct TimeBasedTrigger: Codable, Sendable, Equatable {
    /// Block for N seconds from activation
    public var durationSeconds: Int?
    /// Block until specific time
    public var endTime: Date?

    public init(durationSeconds: Int? = nil, endTime: Date? = nil) {
        self.durationSeconds = durationSeconds
        self.endTime = endTime
    }

    /// Create a trigger for a specific duration
    public static func duration(hours: Int = 0, minutes: Int = 0, seconds: Int = 0) -> TimeBasedTrigger {
        let total = hours * 3600 + minutes * 60 + seconds
        return TimeBasedTrigger(durationSeconds: total)
    }

    /// Create a trigger until a specific time
    public static func until(_ date: Date) -> TimeBasedTrigger {
        return TimeBasedTrigger(endTime: date)
    }
}

// MARK: - Schedule-Based Trigger

/// Configuration for schedule-based triggers
public struct ScheduleBasedTrigger: Codable, Sendable, Equatable {
    /// A time window during which blocking is active
    public struct ScheduleWindow: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var startHour: Int       // 0-23
        public var startMinute: Int     // 0-59
        public var endHour: Int         // 0-23
        public var endMinute: Int       // 0-59
        public var weekdays: Set<Int>   // 1=Sunday, 2=Monday, ..., 7=Saturday

        public init(
            id: UUID = UUID(),
            startHour: Int,
            startMinute: Int,
            endHour: Int,
            endMinute: Int,
            weekdays: Set<Int>
        ) {
            self.id = id
            self.startHour = startHour
            self.startMinute = startMinute
            self.endHour = endHour
            self.endMinute = endMinute
            self.weekdays = weekdays
        }

        /// Convenience for weekday set
        public static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]  // Mon-Fri
        public static let weekendsOnly: Set<Int> = [1, 7]           // Sun, Sat
        public static let everyday: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    }

    public var windows: [ScheduleWindow]

    public init(windows: [ScheduleWindow]) {
        self.windows = windows
    }
}

// MARK: - Block Action

/// Defines what happens when a trigger fires
public enum BlockAction: Codable, Sendable, Hashable, Equatable {
    /// Block the URL pattern's associated domain directly
    case blockDomain
    /// Activate a specific blocklist
    case activateBlocklist(blocklistId: UUID)
}

// MARK: - URL Pattern

/// Pattern for matching URLs (used in visit counting)
public struct URLPattern: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    /// The pattern to match (e.g., "youtube.com/shorts", "twitter.com")
    public var pattern: String
    /// If true, pattern is treated as regex; if false, substring match
    public var isRegex: Bool
    /// Domain to block when threshold is hit (e.g., "youtube.com")
    public var associatedDomain: String
    /// What action to take when threshold is exceeded
    public var blockAction: BlockAction

    public init(
        id: UUID = UUID(),
        pattern: String,
        isRegex: Bool = false,
        associatedDomain: String,
        blockAction: BlockAction = .blockDomain
    ) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.associatedDomain = associatedDomain
        self.blockAction = blockAction
    }

    /// Check if a URL matches this pattern
    public func matches(url: String) -> Bool {
        if isRegex {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return false
            }
            let range = NSRange(url.startIndex..., in: url)
            return regex.firstMatch(in: url, range: range) != nil
        } else {
            return url.lowercased().contains(pattern.lowercased())
        }
    }
}

// MARK: - Visit Count Trigger

/// Configuration for visit-count triggers
public struct VisitCountTrigger: Codable, Sendable, Equatable {
    /// URL patterns to monitor for visits
    public var urlPatterns: [URLPattern]
    /// Number of visits before blocking is triggered
    public var maxVisits: Int
    /// How long to block once triggered (in seconds)
    public var blockDurationSeconds: Int

    public init(
        urlPatterns: [URLPattern],
        maxVisits: Int,
        blockDurationSeconds: Int
    ) {
        self.urlPatterns = urlPatterns
        self.maxVisits = maxVisits
        self.blockDurationSeconds = blockDurationSeconds
    }
}

// MARK: - Independent Trigger

/// A standalone visit-count trigger that is not attached to a blocklist
/// Each URL pattern can independently block its domain or activate a blocklist
public struct IndependentTrigger: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var id: UUID
    /// Display name for this trigger
    public var name: String
    /// URL patterns to monitor - each has its own blockAction
    public var urlPatterns: [URLPattern]
    /// Number of visits before blocking is triggered
    public var maxVisits: Int
    /// How long to block once triggered (in seconds)
    public var blockDurationSeconds: Int
    /// Whether this trigger is currently enabled
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Hour of day (0-23) when visit counts reset
    public var dailyResetHour: Int
    /// Minute of hour (0-59) when visit counts reset
    public var dailyResetMinute: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, urlPatterns, maxVisits, blockDurationSeconds
        case isEnabled, createdAt, updatedAt
        case dailyResetHour, dailyResetMinute
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        urlPatterns = try container.decode([URLPattern].self, forKey: .urlPatterns)
        maxVisits = try container.decode(Int.self, forKey: .maxVisits)
        blockDurationSeconds = try container.decode(Int.self, forKey: .blockDurationSeconds)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dailyResetHour = try container.decodeIfPresent(Int.self, forKey: .dailyResetHour) ?? 6
        dailyResetMinute = try container.decodeIfPresent(Int.self, forKey: .dailyResetMinute) ?? 0
    }

    public init(
        id: UUID = UUID(),
        name: String,
        urlPatterns: [URLPattern],
        maxVisits: Int,
        blockDurationSeconds: Int,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        dailyResetHour: Int = 6,
        dailyResetMinute: Int = 0
    ) {
        self.id = id
        self.name = name
        self.urlPatterns = urlPatterns
        self.maxVisits = maxVisits
        self.blockDurationSeconds = blockDurationSeconds
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dailyResetHour = dailyResetHour
        self.dailyResetMinute = dailyResetMinute
    }
}

// MARK: - Trigger Configuration

/// Unified trigger configuration that can hold any trigger type
public struct TriggerConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var type: TriggerType
    public var timeBased: TimeBasedTrigger?
    public var scheduleBased: ScheduleBasedTrigger?
    public var visitCount: VisitCountTrigger?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        type: TriggerType,
        timeBased: TimeBasedTrigger? = nil,
        scheduleBased: ScheduleBasedTrigger? = nil,
        visitCount: VisitCountTrigger? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.timeBased = timeBased
        self.scheduleBased = scheduleBased
        self.visitCount = visitCount
        self.isEnabled = isEnabled
    }

    /// Convenience initializer for time-based trigger
    public static func timeBased(_ trigger: TimeBasedTrigger, isEnabled: Bool = true) -> TriggerConfig {
        TriggerConfig(type: .timeBased, timeBased: trigger, isEnabled: isEnabled)
    }

    /// Convenience initializer for schedule-based trigger
    public static func scheduleBased(_ trigger: ScheduleBasedTrigger, isEnabled: Bool = true) -> TriggerConfig {
        TriggerConfig(type: .scheduleBased, scheduleBased: trigger, isEnabled: isEnabled)
    }

    /// Convenience initializer for visit-count trigger
    public static func visitCount(_ trigger: VisitCountTrigger, isEnabled: Bool = true) -> TriggerConfig {
        TriggerConfig(type: .visitCount, visitCount: trigger, isEnabled: isEnabled)
    }
}

// MARK: - Blocklist Configuration

/// A named blocklist with domains and triggers
public struct BlocklistConfig: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Display name (e.g., "Social Media", "News Sites")
    public var name: String
    /// Domains to block (e.g., ["twitter.com", "facebook.com"])
    public var domains: [String]
    /// Triggers that can activate this blocklist
    public var triggers: [TriggerConfig]
    /// Whether this blocklist is currently being enforced
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        domains: [String],
        triggers: [TriggerConfig] = [],
        isActive: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.domains = domains
        self.triggers = triggers
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Active Block (Runtime State)

/// Represents an active block with expiration - this is the enforced state
public struct ActiveBlock: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Reference to the BlocklistConfig that created this block
    public var blocklistId: UUID
    /// Domains being blocked (snapshot at activation time)
    public var domains: [String]
    /// When the block was activated
    public var startedAt: Date
    /// When the block expires (nil = indefinite, e.g., schedule-based)
    public var expiresAt: Date?
    /// Why this block was created
    public var reason: BlockReason
    /// If true, block cannot be deactivated until expiration (SelfControl behavior)
    public var isLocked: Bool

    public enum BlockReason: String, Codable, Sendable {
        case manualActivation       // User clicked "Start Block"
        case timeBasedTrigger       // Time-based trigger activated
        case scheduleBasedTrigger   // Schedule window is active
        case visitCountTrigger      // Visit threshold was exceeded
    }

    public init(
        id: UUID = UUID(),
        blocklistId: UUID,
        domains: [String],
        startedAt: Date = Date(),
        expiresAt: Date?,
        reason: BlockReason,
        isLocked: Bool = true
    ) {
        self.id = id
        self.blocklistId = blocklistId
        self.domains = domains
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.reason = reason
        self.isLocked = isLocked
    }

    /// Check if this block has expired
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// Remaining time until expiration (nil if indefinite or expired)
    public var remainingTime: TimeInterval? {
        guard let expiresAt, !isExpired else { return nil }
        return expiresAt.timeIntervalSinceNow
    }
}

// MARK: - Visit Record

/// Tracks visits to URL patterns for visit-count triggers
public struct VisitRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    /// Reference to the URLPattern being tracked
    public var patternId: UUID
    /// Cached pattern string for display
    public var pattern: String
    /// Current visit count
    public var visitCount: Int
    /// When the last visit occurred
    public var lastVisitAt: Date
    /// When tracking started (for reset interval calculation)
    public var firstVisitAt: Date
    /// When the last scheduled daily reset occurred (nil = never reset)
    public var lastDailyResetDate: Date?

    private enum CodingKeys: String, CodingKey {
        case id, patternId, pattern, visitCount, lastVisitAt, firstVisitAt, lastDailyResetDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        patternId = try container.decode(UUID.self, forKey: .patternId)
        pattern = try container.decode(String.self, forKey: .pattern)
        visitCount = try container.decode(Int.self, forKey: .visitCount)
        lastVisitAt = try container.decode(Date.self, forKey: .lastVisitAt)
        firstVisitAt = try container.decode(Date.self, forKey: .firstVisitAt)
        lastDailyResetDate = try container.decodeIfPresent(Date.self, forKey: .lastDailyResetDate)
    }

    public init(
        id: UUID = UUID(),
        patternId: UUID,
        pattern: String,
        visitCount: Int = 0,
        lastVisitAt: Date = Date(),
        firstVisitAt: Date = Date(),
        lastDailyResetDate: Date? = nil
    ) {
        self.id = id
        self.patternId = patternId
        self.pattern = pattern
        self.visitCount = visitCount
        self.lastVisitAt = lastVisitAt
        self.firstVisitAt = firstVisitAt
        self.lastDailyResetDate = lastDailyResetDate
    }

    /// Increment visit count
    public mutating func recordVisit() {
        visitCount += 1
        lastVisitAt = Date()
    }

    /// Reset the visit count
    public mutating func reset() {
        visitCount = 0
        firstVisitAt = Date()
        lastVisitAt = Date()
    }

    /// Reset the visit count as part of a scheduled daily reset
    public mutating func dailyReset() {
        reset()
        lastDailyResetDate = Date()
    }
}

// MARK: - Willpower State (Full IPC State)

/// Complete state shared between App and Daemon via file-based IPC
public struct WillpowerState: Codable, Sendable {
    /// All configured blocklists
    public var blocklists: [BlocklistConfig]
    /// Independent visit-count triggers (not attached to blocklists)
    public var independentTriggers: [IndependentTrigger]
    /// Currently active blocks being enforced
    public var activeBlocks: [ActiveBlock]
    /// Visit records for URL pattern tracking
    public var visitRecords: [VisitRecord]
    /// Last state update timestamp
    public var lastUpdated: Date
    /// Daemon version for compatibility checking
    public var daemonVersion: String

    public init(
        blocklists: [BlocklistConfig] = [],
        independentTriggers: [IndependentTrigger] = [],
        activeBlocks: [ActiveBlock] = [],
        visitRecords: [VisitRecord] = [],
        lastUpdated: Date = Date(),
        daemonVersion: String = "1.0.0"
    ) {
        self.blocklists = blocklists
        self.independentTriggers = independentTriggers
        self.activeBlocks = activeBlocks
        self.visitRecords = visitRecords
        self.lastUpdated = lastUpdated
        self.daemonVersion = daemonVersion
    }

    /// Get all domains currently being blocked
    public var allBlockedDomains: Set<String> {
        var domains = Set<String>()
        for block in activeBlocks where !block.isExpired {
            domains.formUnion(block.domains)
        }
        return domains
    }
}

// MARK: - Daemon Commands (App -> Daemon)

/// Commands that the app sends to the daemon
public enum DaemonCommand: Codable, Sendable {
    /// Activate a blocklist with optional trigger configuration
    case activateBlocklist(blocklistId: UUID, trigger: TriggerConfig?, isLocked: Bool)
    /// Deactivate a blocklist (will fail if locked and not expired)
    case deactivateBlocklist(blocklistId: UUID)
    /// Update all blocklist configurations
    case updateBlocklists([BlocklistConfig])
    /// Update all independent triggers
    case updateIndependentTriggers([IndependentTrigger])
    /// Delete a specific independent trigger
    case deleteIndependentTrigger(triggerId: UUID)
    /// Force state sync
    case forceSync
    /// Report a URL visit from the app (app runs BrowserMonitor since it has user session)
    case reportVisit(patternId: UUID, url: String)
}

// MARK: - Command Wrapper

/// Wrapper for commands with metadata for IPC
public struct CommandWrapper: Codable, Sendable, Identifiable {
    public let id: UUID
    public let command: DaemonCommand
    public let timestamp: Date

    public init(id: UUID = UUID(), command: DaemonCommand, timestamp: Date = Date()) {
        self.id = id
        self.command = command
        self.timestamp = timestamp
    }
}
