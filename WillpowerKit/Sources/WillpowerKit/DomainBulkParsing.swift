//
//  DomainBulkParsing.swift
//  WillpowerKit
//
//  Turning free-form text into domains: what the user pastes, or what's in a
//  text/CSV/hosts file they import.
//
//  Lives in the kit rather than the app so the cleaning rules have exactly one
//  definition, shared by the blocklist and allowlist editors and covered by tests.
//

import Foundation

public enum DomainBulkParsing {

    /// Reduce a single entry to a bare hostname: drop the scheme, `www.`, and any path.
    /// This is the canonical implementation -- the app's `cleanDomain` delegates here.
    public static func cleanDomain(_ input: String) -> String {
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
        if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
        if let slash = cleaned.firstIndex(of: "/") { cleaned = String(cleaned[..<slash]) }
        return cleaned
    }

    /// A domain we're willing to store. Deliberately permissive -- this mirrors the
    /// per-field validation the editors already apply, so bulk entry can't sneak in
    /// anything typing one at a time would have rejected.
    public static func isValidDomain(_ domain: String) -> Bool {
        if domain.isEmpty { return false }
        if !domain.contains(".") { return false }
        if domain.contains(" ") { return false }
        if domain.hasPrefix(".") || domain.hasSuffix(".") { return false }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        return !domain.unicodeScalars.contains { !allowed.contains($0) }
    }

    /// Parse a blob of pasted or imported text into cleaned, valid domains.
    ///
    /// Accepts the shapes people actually have on hand: one per line, comma or
    /// space separated, full URLs, `#` comments, and hosts-file lines such as
    /// `0.0.0.0 example.com`. Order is preserved and duplicates are removed.
    public static func parseDomains(fromPastedText text: String) -> [String] {
        var results: [String] = []
        var seen: Set<String> = []

        for rawLine in text.components(separatedBy: .newlines) {
            // strip comments so hosts files and shared lists import cleanly
            let withoutComment = rawLine.components(separatedBy: "#")[0]
            let line = withoutComment.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            var separators = CharacterSet.whitespaces
            separators.insert(charactersIn: ",;")

            var pieces = line.components(separatedBy: separators).filter { !$0.isEmpty }
            if pieces.isEmpty { continue }

            // hosts-file lines put a redirect target first -- that's an artifact of
            // the format, not a site the user wants listed
            if pieces.count > 1, isIPAddress(pieces[0]) {
                pieces.removeFirst()
            }

            for piece in pieces {
                let cleaned = cleanDomain(piece)
                guard isValidDomain(cleaned), !seen.contains(cleaned) else { continue }
                seen.insert(cleaned)
                results.append(cleaned)
            }
        }

        return results
    }

    /// Render domains back out as a plain text file, one per line.
    public static func exportText(for domains: [String]) -> String {
        domains.joined(separator: "\n") + "\n"
    }

    /// Whether a string is a literal IPv4/IPv6 address.
    static func isIPAddress(_ string: String) -> Bool {
        var v4 = in_addr()
        if string.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return true }

        var v6 = in6_addr()
        return string.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1
    }
}
