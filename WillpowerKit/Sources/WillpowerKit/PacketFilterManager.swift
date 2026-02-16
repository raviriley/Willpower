//
//  PacketFilterManager.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/31/25.
//

import Foundation
import os.log

private let logger = WillpowerLogger.packetFilter

/// Manages pf (packet filter) firewall rules for blocking domains at the network level
/// This provides more reliable blocking than hosts file alone, as it blocks TCP/UDP connections
/// even when browsers have cached DNS entries.
///
/// Inspired by SelfControl's PacketFilter implementation.
public final class PacketFilterManager: Sendable {

    // MARK: - Constants

    /// The anchor name for Willpower rules in pf
    public static let anchorName = "com.willpower"

    /// Path to our anchor file
    public static let anchorPath = "/etc/pf.anchors/\(anchorName)"

    /// Path to the main pf configuration
    public static let pfConfPath = "/etc/pf.conf"

    /// Backup path for pf.conf
    public static let pfConfBackupPath = "/etc/pf.conf.willpower.backup"

    /// Essential Apple system domains that should always be accessible when allow list is active
    /// These ensure macOS system services continue to function
    public static let essentialSystemDomains = [
        "apple.com", "icloud.com", "icloud-content.com", "cdn-apple.com",
        "mzstatic.com", "push.apple.com", "gs.apple.com", "swscan.apple.com",
        "swdist.apple.com", "mesu.apple.com", "appldnld.apple.com",
        "configuration.apple.com", "ocsp.apple.com", "ocsp2.apple.com",
        "crl.apple.com", "valid.apple.com", "captive.apple.com",
        "time.apple.com", "lcdn-locator.apple.com", "lcdn-registration.apple.com",
        "xp.apple.com", "aaplimg.com"
    ]

    // MARK: - Errors

    public enum PFError: Error, LocalizedError {
        case permissionDenied
        case pfctlFailed(String)
        case resolutionFailed(String)
        case configurationError(String)

        public var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permission denied - must run as root"
            case .pfctlFailed(let msg):
                return "pfctl command failed: \(msg)"
            case .resolutionFailed(let msg):
                return "DNS resolution failed: \(msg)"
            case .configurationError(let msg):
                return "Configuration error: \(msg)"
            }
        }
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// iCloud Private Relay domains - blocking these disables Private Relay
    /// This is necessary because Private Relay bypasses local network controls
    private static let privateRelayDomains = [
        "mask.icloud.com",
        "mask-h2.icloud.com",
        "mask-api.icloud.com",
        "mask.apple-dns.net"
    ]

    /// Start blocking the given domains using pf firewall
    /// - Parameter domains: Array of domain names to block
    public func startBlock(domains: [String]) throws {
        guard getuid() == 0 else {
            throw PFError.permissionDenied
        }

        // Resolve all domains to IP addresses
        var allIPs = Set<String>()
        for domain in domains {
            let ips = resolveHostname(domain)
            allIPs.formUnion(ips)

            // Also resolve www variant
            if !domain.hasPrefix("www.") {
                let wwwIPs = resolveHostname("www.\(domain)")
                allIPs.formUnion(wwwIPs)
            }
        }

        // Also resolve and block iCloud Private Relay infrastructure
        // This disables Private Relay so Safari respects our blocks
        logger.info("Blocking iCloud Private Relay to ensure Safari blocking works")
        for relayDomain in Self.privateRelayDomains {
            let relayIPs = resolveHostname(relayDomain)
            allIPs.formUnion(relayIPs)
        }

        guard !allIPs.isEmpty else {
            logger.warning("No IPs resolved for domains, skipping pf rules")
            return
        }

        // Generate pf rules
        let rules = generateRules(for: Array(allIPs))

        // Write anchor file
        try writeAnchorFile(rules: rules)

        // Add anchor reference to pf.conf if not present
        try ensureAnchorInPfConf()

        // Enable pf and load rules
        try enablePF()

        logger.info("Started blocking \(allIPs.count) IPs for \(domains.count) domains (+ Private Relay)")
    }

    /// Stop all Willpower pf blocking
    public func stopBlock() throws {
        guard getuid() == 0 else {
            throw PFError.permissionDenied
        }

        // Clear the anchor file (write empty rules)
        try writeAnchorFile(rules: "")

        // Reload pf to apply empty rules
        try reloadAnchor()

        logger.info("Stopped pf blocking")
    }

    /// Apply unified PF rules handling both blocklists and allowlists
    /// - Parameters:
    ///   - blockedDomains: Domains to block (from .block mode blocklists)
    ///   - allowedDomains: Domains to allow (from .allow mode allowlists)
    ///   - isAllowListActive: Whether any allow list is currently active
    public func applyRules(blockedDomains: [String], allowedDomains: [String], isAllowListActive: Bool) throws {
        guard getuid() == 0 else {
            throw PFError.permissionDenied
        }

        // If nothing to enforce, clear rules
        if blockedDomains.isEmpty && !isAllowListActive {
            try stopBlock()
            return
        }

        // Resolve blocked domain IPs
        var blockedIPs = Set<String>()
        for domain in blockedDomains {
            blockedIPs.formUnion(resolveHostname(domain))
            if !domain.hasPrefix("www.") {
                blockedIPs.formUnion(resolveHostname("www.\(domain)"))
            }
        }

        // Also resolve and block iCloud Private Relay infrastructure
        for relayDomain in Self.privateRelayDomains {
            blockedIPs.formUnion(resolveHostname(relayDomain))
        }

        // Resolve allowed domain IPs (only if allow list active)
        var allowedIPs = Set<String>()
        if isAllowListActive {
            for domain in allowedDomains {
                allowedIPs.formUnion(resolveHostname(domain))
                if !domain.hasPrefix("www.") {
                    allowedIPs.formUnion(resolveHostname("www.\(domain)"))
                }
            }

            // Resolve essential system domain IPs
            for domain in Self.essentialSystemDomains {
                allowedIPs.formUnion(resolveHostname(domain))
                allowedIPs.formUnion(resolveHostname("www.\(domain)"))
            }

            // Remove any IPs that are in the blocked set (block wins)
            allowedIPs.subtract(blockedIPs)
        }

        // Generate unified ruleset
        let rules = generateUnifiedRules(
            blockedIPs: Array(blockedIPs),
            allowedIPs: Array(allowedIPs),
            isAllowListActive: isAllowListActive
        )

        // Write anchor file
        try writeAnchorFile(rules: rules)

        // Add anchor reference to pf.conf if not present
        try ensureAnchorInPfConf()

        // Enable pf and load rules
        try enablePF()

        logger.info("Applied unified rules: \(blockedIPs.count) blocked IPs, \(allowedIPs.count) allowed IPs, allowList=\(isAllowListActive)")
    }

    /// Check if Willpower pf rules are currently active
    public func isBlockActive() -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = ["-a", Self.anchorName, "-sr"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // If there are rules in the anchor, blocking is active
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    /// Resolve a hostname to IP addresses using external DNS (bypasses hosts file)
    private func resolveHostname(_ hostname: String) -> [String] {
        var ips: [String] = []

        // Use dig to query external DNS directly, bypassing hosts file
        // This is critical because the hosts file may already have the domain blocked
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        // Query Google's DNS directly to bypass local hosts file
        process.arguments = ["+short", "@8.8.8.8", hostname, "A"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Only add valid IPv4 addresses (not CNAMEs or empty lines)
                    if !trimmed.isEmpty && trimmed.range(of: "^[0-9.]+$", options: .regularExpression) != nil {
                        ips.append(trimmed)
                    }
                }
            }
        } catch {
            logger.debug("dig failed for \(hostname): \(error.localizedDescription)")
        }

        // Also resolve IPv6 addresses
        let process6 = Process()
        let pipe6 = Pipe()

        process6.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
        process6.arguments = ["+short", "@8.8.8.8", hostname, "AAAA"]
        process6.standardOutput = pipe6
        process6.standardError = FileHandle.nullDevice

        do {
            try process6.run()
            process6.waitUntilExit()

            let data = pipe6.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Only add valid IPv6 addresses
                    if !trimmed.isEmpty && trimmed.contains(":") {
                        ips.append(trimmed)
                    }
                }
            }
        } catch {
            logger.debug("dig AAAA failed for \(hostname): \(error.localizedDescription)")
        }

        if ips.isEmpty {
            logger.debug("No IPs resolved for \(hostname)")
        } else {
            logger.debug("Resolved \(hostname) -> \(ips)")
        }

        return ips
    }

    /// Generate unified PF ruleset for both block and allow modes
    private func generateUnifiedRules(blockedIPs: [String], allowedIPs: [String], isAllowListActive: Bool) -> String {
        var rules: [String] = []

        // Section 1: Infrastructure (always allowed)
        rules.append("# Infrastructure - always allowed")
        rules.append("pass out quick on lo0 all")
        rules.append("pass out quick proto udp from any to any port 53")
        rules.append("pass out quick proto tcp from any to any port 53")
        rules.append("pass out quick proto udp from any to any port { 67, 68 }")
        rules.append("pass out quick proto { tcp, udp } from any to 10.0.0.0/8")
        rules.append("pass out quick proto { tcp, udp } from any to 172.16.0.0/12")
        rules.append("pass out quick proto { tcp, udp } from any to 192.168.0.0/16")

        // Section 2: Explicitly blocked domain IPs (block wins over allow)
        if !blockedIPs.isEmpty {
            rules.append("")
            rules.append("# Blocked domains")
            for ip in blockedIPs {
                rules.append("block return out quick proto tcp from any to \(ip)")
                rules.append("block return out quick proto udp from any to \(ip)")
            }
        }

        // Sections 3-4: Only when allow list is active
        if isAllowListActive {
            // Section 3: Allowed domain IPs
            if !allowedIPs.isEmpty {
                rules.append("")
                rules.append("# Allowed domains (allow list)")
                for ip in allowedIPs {
                    rules.append("pass out quick proto { tcp, udp } from any to \(ip)")
                }
            }

            // Section 4: Block all other web traffic
            rules.append("")
            rules.append("# Block all other web traffic (allow list enforcement)")
            rules.append("block return out quick proto tcp from any to any port { 80, 443 }")
            rules.append("block return out quick proto udp from any to any port { 80, 443 }")
        }

        return rules.joined(separator: "\n") + "\n"
    }

    /// Generate pf rules for blocking IPs
    private func generateRules(for ips: [String]) -> String {
        var rules: [String] = []

        for ip in ips {
            // Block both TCP and UDP, return RST/ICMP for cleaner connection failures
            // "block return" sends RST for TCP and ICMP unreachable for UDP
            rules.append("block return out proto tcp from any to \(ip)")
            rules.append("block return out proto udp from any to \(ip)")
        }

        return rules.joined(separator: "\n") + "\n"
    }

    /// Write rules to the anchor file
    private func writeAnchorFile(rules: String) throws {
        let url = URL(fileURLWithPath: Self.anchorPath)

        do {
            try rules.write(to: url, atomically: true, encoding: .utf8)
            // Set appropriate permissions
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: Self.anchorPath)
        } catch {
            throw PFError.configurationError("Failed to write anchor file: \(error.localizedDescription)")
        }
    }

    /// Ensure our anchor is referenced in pf.conf
    private func ensureAnchorInPfConf() throws {
        let anchorLine = "anchor \"\(Self.anchorName)\""
        let loadLine = "load anchor \"\(Self.anchorName)\" from \"\(Self.anchorPath)\""

        let url = URL(fileURLWithPath: Self.pfConfPath)
        var contents: String

        do {
            contents = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw PFError.configurationError("Failed to read pf.conf: \(error.localizedDescription)")
        }

        // Check if our anchor is already present
        if contents.contains(anchorLine) {
            return  // Already configured
        }

        // Backup original pf.conf
        let backupURL = URL(fileURLWithPath: Self.pfConfBackupPath)
        if !FileManager.default.fileExists(atPath: Self.pfConfBackupPath) {
            try? contents.write(to: backupURL, atomically: true, encoding: .utf8)
        }

        // Add our anchor at the end
        var newContents = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        newContents += "\n\n# Willpower blocking rules\n"
        newContents += "\(anchorLine)\n"
        newContents += "\(loadLine)\n"

        do {
            try newContents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw PFError.configurationError("Failed to update pf.conf: \(error.localizedDescription)")
        }
    }

    /// Enable pf and load configuration (matching SelfControl's approach)
    private func enablePF() throws {
        // Use -E (reference-counted enable) with -f (load config) and -F states (flush)
        // This matches SelfControl's implementation: pfctl -E -f /etc/pf.conf -F states
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = ["-E", "-f", Self.pfConfPath, "-F", "states"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        logger.info("pf enabled and rules loaded (pfctl -E -f -F states)")
    }

    /// Reload just our anchor (used when updating rules)
    private func reloadAnchor() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        process.arguments = ["-a", Self.anchorName, "-f", Self.anchorPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        // Also flush states to break existing connections
        let flushProcess = Process()
        flushProcess.executableURL = URL(fileURLWithPath: "/sbin/pfctl")
        flushProcess.arguments = ["-F", "states"]
        flushProcess.standardOutput = FileHandle.nullDevice
        flushProcess.standardError = FileHandle.nullDevice

        try? flushProcess.run()
        flushProcess.waitUntilExit()
    }
}

// MARK: - Convenience Extensions

extension PacketFilterManager {
    /// Update blocking with new domains (stops existing block and starts new one)
    public func updateBlock(domains: [String]) throws {
        if domains.isEmpty {
            try stopBlock()
        } else {
            try startBlock(domains: domains)
        }
    }
}
