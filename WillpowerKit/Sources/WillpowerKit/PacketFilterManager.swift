//
//  PacketFilterManager.swift
//  WillpowerKit
//
//  Created by Ravi Riley on 12/31/25.
//

import Foundation

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

        guard !allIPs.isEmpty else {
            print("[PacketFilterManager] No IPs resolved for domains, skipping pf rules")
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

        print("[PacketFilterManager] Started blocking \(allIPs.count) IPs for \(domains.count) domains")
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

        print("[PacketFilterManager] Stopped pf blocking")
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

    /// Get the IPs currently blocked by pf
    public func getBlockedIPs() -> [String] {
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

            // Parse IPs from rules like "block return out proto tcp from any to 1.2.3.4"
            var ips = Set<String>()
            for line in output.components(separatedBy: .newlines) {
                if let range = line.range(of: "to ([0-9.]+|[0-9a-f:]+)", options: .regularExpression) {
                    let ipPart = String(line[range]).replacingOccurrences(of: "to ", with: "")
                    ips.insert(ipPart)
                }
            }
            return Array(ips)
        } catch {
            return []
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
            print("[PacketFilterManager] dig failed for \(hostname): \(error)")
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
            print("[PacketFilterManager] dig AAAA failed for \(hostname): \(error)")
        }

        if ips.isEmpty {
            print("[PacketFilterManager] No IPs resolved for \(hostname)")
        } else {
            print("[PacketFilterManager] Resolved \(hostname) -> \(ips)")
        }

        return ips
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

        print("[PacketFilterManager] pf enabled and rules loaded (pfctl -E -f -F states)")
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
