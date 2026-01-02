//
//  BlocklistEditorSheet.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

// MARK: - Blocklist Presets

enum BlocklistPreset: String, CaseIterable, Identifiable {
    case socialMedia = "Social Media"
    case news = "News & Reddit"
    case video = "Videos & Streaming"
    case gaming = "Gaming"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .socialMedia: return "bubble.left.and.bubble.right"
        case .news: return "newspaper"
        case .video: return "play.rectangle"
        case .gaming: return "gamecontroller"
        }
    }

    var domains: [String] {
        switch self {
        case .socialMedia:
            return [
                "twitter.com", "x.com", "facebook.com", "instagram.com",
                "tiktok.com", "snapchat.com", "linkedin.com", "threads.com", "reddit.com"
            ]
        case .news:
            return [
                "reddit.com", "news.ycombinator.com", "cnn.com", "nytimes.com",
                "bbc.com", "foxnews.com", "theguardian.com", "washingtonpost.com"
            ]
        case .video:
            return [
                "youtube.com", "netflix.com", "hulu.com", "disneyplus.com",
                "primevideo.com", "hbomax.com", "peacocktv.com",
                "twitch.tv", "rumble.com", "kick.com", "parti.com"
            ]
        case .gaming:
            return [
                "steampowered.com", "discord.com", "twitch.tv",
                "epicgames.com", "roblox.com", "ea.com", "battle.net"
            ]
        }
    }

    var description: String {
        switch self {
        case .socialMedia:
            return "Block social media platforms"
        case .news:
            return "Block news sites and Reddit"
        case .video:
            return "Block video streaming services"
        case .gaming:
            return "Block gaming platforms"
        }
    }
}

struct BlocklistEditorSheet: View {
    @Bindable var viewModel: WillpowerViewModel
    let blocklist: BlocklistConfig?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var domains: [String] = []
    @State private var newDomain: String = ""
    @State private var domainValidationError: String?
    /// Domains that existed when editing started (cannot be removed if active)
    @State private var originalDomains: Set<String> = []

    var isEditing: Bool { blocklist != nil }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Check if this blocklist has an active (non-expired) block
    var isBlocklistActive: Bool {
        guard let blocklist else { return false }
        return viewModel.activeBlocks.contains { $0.blocklistId == blocklist.id && !$0.isExpired }
    }

    /// Check if a domain can be deleted (only new domains when active)
    func canDeleteDomain(_ domain: String) -> Bool {
        if !isBlocklistActive { return true }
        return !originalDomains.contains(domain)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Blocklist Name", text: $name)
                        .textFieldStyle(.plain)
                }

                // Preset templates (only show when creating new blocklist)
                if !isEditing && domains.isEmpty {
                    Section("Start from Template") {
                        ForEach(BlocklistPreset.allCases) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                HStack {
                                    Image(systemName: preset.icon)
                                        .foregroundStyle(.blue)
                                        .frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(preset.rawValue)
                                            .foregroundStyle(.primary)
                                        Text("\(preset.domains.count) sites")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Active blocklist warning banner
                if isBlocklistActive {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Blocklist is Active")
                                    .font(.headline)
                                Text("You can add new domains but cannot remove existing ones until the block expires.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Domains") {
                    ForEach(domains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                                .font(.system(.body, design: .monospaced))

                            Spacer()

                            if canDeleteDomain(domain) {
                                Button(role: .destructive) {
                                    domains.removeAll { $0 == domain }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Show lock icon for protected domains
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .help("Cannot remove while blocklist is active")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Add domain (e.g., youtube.com)", text: $newDomain)
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    addDomain()
                                }
                                .onChange(of: newDomain) { _, _ in
                                    // Clear error when user starts typing
                                    domainValidationError = nil
                                }

                            Button("Add") {
                                addDomain()
                            }
                            .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if let error = domainValidationError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    if isBlocklistActive {
                        Text("New domains will be blocked immediately when saved.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("You can paste URLs and they will be cleaned automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Blocklist" : "New Blocklist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .onAppear {
            if let blocklist {
                name = blocklist.name
                domains = blocklist.domains
                // Store original domains to prevent removal when active
                originalDomains = Set(blocklist.domains)
            }
        }
    }

    private func applyPreset(_ preset: BlocklistPreset) {
        // Set name from preset if empty
        if name.isEmpty {
            name = preset.rawValue
        }
        // Add all preset domains (avoiding duplicates)
        for domain in preset.domains {
            if !domains.contains(domain) {
                domains.append(domain)
            }
        }
    }

    private func addDomain() {
        let cleaned = cleanDomain(newDomain)

        // Validate the cleaned domain
        if cleaned.isEmpty {
            domainValidationError = "Please enter a domain"
            return
        }

        if domains.contains(cleaned) {
            domainValidationError = "This domain is already in the list"
            newDomain = ""
            return
        }

        // Basic domain format validation
        if let validationError = validateDomainFormat(cleaned) {
            domainValidationError = validationError
            return
        }

        domains.append(cleaned)
        newDomain = ""
        domainValidationError = nil
    }

    private func validateDomainFormat(_ domain: String) -> String? {
        // Check for spaces
        if domain.contains(" ") {
            return "Domain cannot contain spaces"
        }

        // Check for basic domain format (at least one dot)
        if !domain.contains(".") {
            return "Invalid domain format. Example: youtube.com"
        }

        // Check for valid characters (alphanumeric, hyphens, dots)
        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        if domain.unicodeScalars.contains(where: { !validCharacters.contains($0) }) {
            return "Domain contains invalid characters"
        }

        // Check for consecutive dots or starting/ending with dot/hyphen
        if domain.contains("..") {
            return "Domain cannot contain consecutive dots"
        }

        if domain.hasPrefix(".") || domain.hasSuffix(".") {
            return "Domain cannot start or end with a dot"
        }

        if domain.hasPrefix("-") || domain.hasSuffix("-") {
            return "Domain cannot start or end with a hyphen"
        }

        // Check TLD exists (at least 2 characters after last dot)
        if let lastDot = domain.lastIndex(of: ".") {
            let tld = String(domain[domain.index(after: lastDot)...])
            if tld.count < 2 {
                return "Invalid top-level domain"
            }
        }

        return nil
    }

    private func save() {
        if var existing = blocklist {
            existing.name = name
            existing.domains = domains
            viewModel.updateBlocklist(existing)
        } else {
            viewModel.createBlocklist(name: name, domains: domains)
        }
        dismiss()
    }

    private func cleanDomain(_ input: String) -> String {
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
        if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
        if let slash = cleaned.firstIndex(of: "/") { cleaned = String(cleaned[..<slash]) }
        return cleaned
    }
}

#Preview {
    BlocklistEditorSheet(viewModel: WillpowerViewModel(), blocklist: nil)
}
