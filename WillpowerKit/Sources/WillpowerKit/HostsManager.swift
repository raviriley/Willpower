//
//  HostsManager.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/29/25.
//

import Foundation

/// Manages reading/writing to /etc/hosts with WILLPOWER markers
public final class HostsManager: Sendable {

    // MARK: - Constants

    public static let hostsPath = "/etc/hosts"
    public static let markerStart = "## WILLPOWER-START"
    public static let markerEnd = "## WILLPOWER-END"

    /// Lock file for concurrent access protection
    private static let lockPath = "/tmp/willpower_hosts.lock"

    // MARK: - Errors

    public enum HostsError: Error, LocalizedError {
        case fileNotFound
        case readError(underlying: Error)
        case writeError(underlying: Error)
        case lockAcquisitionFailed
        case invalidHostsFormat
        case permissionDenied

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Hosts file not found at /etc/hosts"
            case .readError(let e):
                return "Failed to read hosts file: \(e.localizedDescription)"
            case .writeError(let e):
                return "Failed to write hosts file: \(e.localizedDescription)"
            case .lockAcquisitionFailed:
                return "Could not acquire lock for hosts file modification"
            case .invalidHostsFormat:
                return "Hosts file has invalid format"
            case .permissionDenied:
                return "Permission denied - daemon must run as root"
            }
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Reads the current hosts file and returns Willpower-managed domains
    public func readManagedDomains() throws -> [String] {
        let contents = try readHostsFile()
        return extractManagedDomains(from: contents)
    }

    /// Applies the given domains to /etc/hosts within WILLPOWER markers
    /// - Parameter domains: Array of domain names to block (e.g., ["twitter.com", "facebook.com"])
    public func applyBlocklist(domains: [String]) throws {
        try withFileLock {
            var contents = try readHostsFile()

            // Remove existing Willpower block if present
            contents = removeWillpowerBlock(from: contents)

            // If no domains to block, we're done
            guard !domains.isEmpty else {
                try writeHostsFile(contents)
                return
            }

            // Generate new block entries
            let blockEntries = generateBlockEntries(for: domains)

            // Append new block with proper spacing
            var newContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newContents.isEmpty {
                newContents += "\n\n"
            }
            newContents += Self.markerStart + "\n"
            newContents += blockEntries
            newContents += Self.markerEnd + "\n"

            try writeHostsFile(newContents)
        }
    }

    /// Removes all Willpower-managed entries from /etc/hosts
    public func removeAllBlocks() throws {
        try withFileLock {
            let contents = try readHostsFile()
            let cleaned = removeWillpowerBlock(from: contents)
            try writeHostsFile(cleaned)
        }
    }

    /// Checks if Willpower block currently exists in hosts file
    public func hasActiveBlocks() throws -> Bool {
        let contents = try readHostsFile()
        return contents.contains(Self.markerStart)
    }

    /// Flushes DNS cache after modifying hosts file
    /// This ensures changes take effect immediately
    /// Note: This flushes system DNS cache but browsers may have their own caches
    public func flushDNSCache() throws {
        // Flush the system DNS cache
        let dscacheutil = Process()
        dscacheutil.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        dscacheutil.arguments = ["-flushcache"]
        try dscacheutil.run()
        dscacheutil.waitUntilExit()

        // Signal mDNSResponder to reload (primary DNS resolver on macOS)
        let killallMDNS = Process()
        killallMDNS.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killallMDNS.arguments = ["-HUP", "mDNSResponder"]
        try? killallMDNS.run()
        killallMDNS.waitUntilExit()

        // Also restart mDNSResponderHelper if it exists (helps with some macOS versions)
        let killallHelper = Process()
        killallHelper.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killallHelper.arguments = ["-HUP", "mDNSResponderHelper"]
        try? killallHelper.run()
        killallHelper.waitUntilExit()

        // Flush the DNS service discovery daemon
        let discoveryKill = Process()
        discoveryKill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        discoveryKill.arguments = ["-HUP", "discoveryd"]
        try? discoveryKill.run()  // Only exists on older macOS
        discoveryKill.waitUntilExit()

        // Use lookupd flush for older compatibility
        let lookupdFlush = Process()
        lookupdFlush.executableURL = URL(fileURLWithPath: "/usr/sbin/lookupd")
        lookupdFlush.arguments = ["-flushcache"]
        try? lookupdFlush.run()  // Only exists on very old macOS
        lookupdFlush.waitUntilExit()

        print("[HostsManager] DNS cache flushed")
    }

    /// Note about browser DNS caches
    /// Browser DNS caches are handled by the PF firewall layer which blocks
    /// at the network level regardless of cached DNS entries.
    public func attemptBrowserDNSFlush() {
        // Browser DNS caches are now bypassed by the PF firewall layer
        // which blocks TCP/UDP connections by IP address.
        // No AppKit/AppleScript needed - this runs safely in daemon context.
        print("[HostsManager] Note: Browser DNS caches bypassed via PF firewall")
    }

    /// Convenience method to apply domains and flush DNS in one call
    public func applyBlocklistAndFlush(domains: [String]) throws {
        try applyBlocklist(domains: domains)
        try flushDNSCache()
        attemptBrowserDNSFlush()
    }

    // MARK: - Private Helpers

    private func readHostsFile() throws -> String {
        let url = URL(fileURLWithPath: Self.hostsPath)

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                throw HostsError.fileNotFound
            } else if error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES) {
                throw HostsError.permissionDenied
            } else {
                throw HostsError.readError(underlying: error)
            }
        }
    }

    private func writeHostsFile(_ contents: String) throws {
        let url = URL(fileURLWithPath: Self.hostsPath)

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES) {
                throw HostsError.permissionDenied
            } else {
                throw HostsError.writeError(underlying: error)
            }
        }
    }

    private func extractManagedDomains(from contents: String) -> [String] {
        guard let startRange = contents.range(of: Self.markerStart),
              let endRange = contents.range(of: Self.markerEnd),
              startRange.upperBound < endRange.lowerBound else {
            return []
        }

        let blockContent = String(contents[startRange.upperBound..<endRange.lowerBound])
        let validIPs: Set<String> = ["127.0.0.1", "0.0.0.0", "::1", "::"]

        return blockContent
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

                // Parse "127.0.0.1 domain.com" or "0.0.0.0 domain.com" or "::1 domain.com"
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { return nil }

                let ip = String(parts[0])
                guard validIPs.contains(ip) else { return nil }

                return String(parts[1])
            }
    }

    private func removeWillpowerBlock(from contents: String) -> String {
        guard let startRange = contents.range(of: Self.markerStart),
              let endRange = contents.range(of: Self.markerEnd) else {
            return contents
        }

        // Include any trailing newline after the end marker
        var removeEnd = endRange.upperBound
        if removeEnd < contents.endIndex && contents[removeEnd] == "\n" {
            removeEnd = contents.index(after: removeEnd)
        }

        // Also remove preceding blank lines to avoid gaps
        var removeStart = startRange.lowerBound
        while removeStart > contents.startIndex {
            let prev = contents.index(before: removeStart)
            if contents[prev] == "\n" {
                removeStart = prev
            } else {
                break
            }
        }

        var result = contents
        result.removeSubrange(removeStart..<removeEnd)
        return result
    }

    private func generateBlockEntries(for domains: [String]) -> String {
        // Deduplicate and normalize domains
        var uniqueDomains = Set<String>()

        for domain in domains {
            var cleaned = domain.lowercased().trimmingCharacters(in: .whitespaces)

            // Remove protocol if present
            if cleaned.hasPrefix("http://") {
                cleaned = String(cleaned.dropFirst(7))
            } else if cleaned.hasPrefix("https://") {
                cleaned = String(cleaned.dropFirst(8))
            }

            // Remove trailing slash and path
            if let slashIndex = cleaned.firstIndex(of: "/") {
                cleaned = String(cleaned[..<slashIndex])
            }

            // Remove www. prefix for the base domain
            let baseDomain = cleaned.hasPrefix("www.") ? String(cleaned.dropFirst(4)) : cleaned

            guard !baseDomain.isEmpty else { continue }
            uniqueDomains.insert(baseDomain)
        }

        // Generate entries for each domain
        // Use both 127.0.0.1 and 0.0.0.0 for IPv4 blocking
        // Use ::1 and :: for IPv6 blocking (critical - browsers use IPv6!)
        // Also block www. variants
        var entries: [String] = []

        for domain in uniqueDomains.sorted() {
            // IPv4 blocking
            entries.append("127.0.0.1 \(domain)")
            entries.append("127.0.0.1 www.\(domain)")
            entries.append("0.0.0.0 \(domain)")
            entries.append("0.0.0.0 www.\(domain)")
            // IPv6 blocking
            entries.append("::1 \(domain)")
            entries.append("::1 www.\(domain)")
            entries.append(":: \(domain)")
            entries.append(":: www.\(domain)")
        }

        return entries.joined(separator: "\n") + "\n"
    }

    // MARK: - File Locking

    private func withFileLock<T>(_ operation: () throws -> T) throws -> T {
        // Create lock file if it doesn't exist
        let lockFD = open(Self.lockPath, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else {
            throw HostsError.lockAcquisitionFailed
        }
        defer { close(lockFD) }

        // Acquire exclusive lock (blocking)
        guard flock(lockFD, LOCK_EX) == 0 else {
            throw HostsError.lockAcquisitionFailed
        }
        defer { flock(lockFD, LOCK_UN) }

        return try operation()
    }
}

// MARK: - Convenience Extensions

extension HostsManager {
    /// Check if a specific domain is currently blocked
    public func isDomainBlocked(_ domain: String) throws -> Bool {
        let managedDomains = try readManagedDomains()
        let normalizedDomain = domain.lowercased()
        let normalizedWithWWW = "www.\(normalizedDomain)"

        return managedDomains.contains { managed in
            managed == normalizedDomain || managed == normalizedWithWWW
        }
    }

    /// Get a formatted string of all blocked domains (for debugging)
    public func getBlockedDomainsDescription() throws -> String {
        let domains = try readManagedDomains()
        if domains.isEmpty {
            return "No domains currently blocked by Willpower"
        }

        // Filter to unique base domains (remove duplicates from www variants)
        let baseDomains = Set(domains.map { domain -> String in
            if domain.hasPrefix("www.") {
                return String(domain.dropFirst(4))
            }
            return domain
        }).sorted()

        return "Blocked domains (\(baseDomains.count)):\n" + baseDomains.map { "  - \($0)" }.joined(separator: "\n")
    }
}
