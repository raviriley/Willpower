//
//  DomainUtilities.swift
//  Willpower
//
//  Shared domain/URL cleaning utilities used across multiple views.
//

import Foundation

/// Clean a domain string by removing protocol, www prefix, and paths
/// - Parameter input: Raw domain or URL string
/// - Returns: Cleaned domain (e.g., "twitter.com")
func cleanDomain(_ input: String) -> String {
    var cleaned: String = input.lowercased().trimmingCharacters(in: .whitespaces)
    if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
    if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
    if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
    if let slash = cleaned.firstIndex(of: "/") { cleaned = String(cleaned[..<slash]) }
    return cleaned
}

/// Clean a URL pattern by removing protocol and www prefix (keeps path)
/// - Parameter input: Raw URL pattern string
/// - Returns: Cleaned pattern (e.g., "youtube.com/shorts")
func cleanURLPattern(_ input: String) -> String {
    var cleaned = input.lowercased().trimmingCharacters(in: .whitespaces)
    if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
    if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
    if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
    return cleaned
}

/// Extract domain from a URL pattern (strips path)
/// - Parameter pattern: URL pattern string
/// - Returns: Domain portion only
func extractDomain(from pattern: String) -> String {
    var domain = pattern.lowercased()
    if domain.hasPrefix("http://") { domain = String(domain.dropFirst(7)) }
    if domain.hasPrefix("https://") { domain = String(domain.dropFirst(8)) }
    if domain.hasPrefix("www.") { domain = String(domain.dropFirst(4)) }
    if let slash = domain.firstIndex(of: "/") { domain = String(domain[..<slash]) }
    return domain
}
