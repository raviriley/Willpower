//
//  BlocklistDetailView.swift
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

// MARK: - BlocklistDetailView

struct BlocklistDetailView: View {
    @Bindable var viewModel: WillpowerViewModel
    let blocklistId: UUID

    @State private var isShowingDeactivateConfirmation = false
    @State private var isShowingDeleteConfirmation = false

    // Inline editing state
    @State private var name: String = ""
    @State private var domains: [String] = []
    @State private var newDomain: String = ""
    @State private var domainValidationError: String?
    @State private var originalDomains: Set<String> = []

    /// Get the current blocklist from viewModel (always fresh)
    var blocklist: BlocklistConfig? {
        viewModel.blocklists.first { $0.id == blocklistId }
    }

    var activeBlock: ActiveBlock? {
        guard let blocklist else { return nil }
        return viewModel.activeBlock(for: blocklist)
    }

    /// Check if this blocklist has an active (non-expired) block
    var isBlocklistActive: Bool {
        activeBlock != nil
    }

    /// Check if a domain can be deleted (only new domains when active)
    func canDeleteDomain(_ domain: String) -> Bool {
        if !isBlocklistActive { return true }
        return !originalDomains.contains(domain)
    }

    /// Independent triggers that target this blocklist
    var targetingTriggers: [IndependentTrigger] {
        guard let blocklist else { return [] }
        return viewModel.independentTriggers.filter { trigger in
            trigger.urlPatterns.contains { pattern in
                if case .activateBlocklist(let targetId) = pattern.blockAction {
                    return targetId == blocklist.id
                }
                return false
            }
        }
    }

    var body: some View {
        Group {
            if let blocklist {
                Form {
                    // Name Section
                    Section("Name") {
                        TextField("Blocklist Name", text: $name)
                            .textFieldStyle(.plain)
                            .onChange(of: name) { _, newValue in
                                saveIfValid()
                            }
                    }

                    // Status & Actions Section
                    Section("Status") {
                        if let activeBlock {
                            // Active state UI
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        StatusBadge(
                                            text: activeBlock.isLocked ? "LOCKED" : "ACTIVE",
                                            color: activeBlock.isLocked ? .red : .orange
                                        )
                                        Text(activeBlock.reason.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let expiresAt = activeBlock.expiresAt {
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            TimeRemainingView(expiresAt: expiresAt)
                                        }
                                    } else {
                                        Text("Indefinite duration")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if activeBlock.isLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(.vertical, 4)

                            if activeBlock.isLocked {
                                Label {
                                    Text("This block cannot be deactivated until it expires")
                                        .font(.callout)
                                } icon: {
                                    Image(systemName: "info.circle")
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Button("Deactivate Block", role: .destructive) {
                                    isShowingDeactivateConfirmation = true
                                }
                            }
                        } else {
                            // Inactive state UI
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Inactive")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("This blocklist is not currently blocking any domains")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)

                            Button {
                                viewModel.isShowingActivationSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Activate Now")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }

                    // Triggers Section
                    Section {
                        if blocklist.triggers.isEmpty && targetingTriggers.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "bolt.slash")
                                        .foregroundStyle(.secondary)
                                    Text("No triggers configured")
                                        .foregroundStyle(.secondary)
                                }
                                Text("Triggers automatically activate this blocklist based on schedules or visit counts.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            // Embedded triggers (schedules, etc.)
                            ForEach(blocklist.triggers) { trigger in
                                TriggerSummaryRow(
                                    trigger: trigger,
                                    blocklist: blocklist,
                                    viewModel: viewModel
                                )
                            }

                            // Independent triggers that target this blocklist
                            ForEach(targetingTriggers) { trigger in
                                IndependentTriggerSummaryRow(
                                    trigger: trigger,
                                    viewModel: viewModel
                                )
                            }
                        }
                    } header: {
                        Text("Triggers")
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

                    // Preset templates (only show when no domains yet)
                    if domains.isEmpty && !isBlocklistActive {
                        Section("Start from Template") {
                            ForEach(BlocklistPreset.allCases) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    HStack {
                                        Image(systemName: preset.icon)
                                            .foregroundStyle(Color.accentColor)
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
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Domains Section (editable)
                    Section {
                        ForEach(domains, id: \.self) { domain in
                            HStack {
                                Text(domain)
                                    .font(.system(.body, design: .monospaced))

                                Spacer()

                                if canDeleteDomain(domain) {
                                    Button(role: .destructive) {
                                        domains.removeAll { $0 == domain }
                                        saveIfValid()
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                        .help("Cannot remove while blocklist is active")
                                }
                            }
                        }

                        // Add new domain
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                TextField("Add domain", text: $newDomain)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .default))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .onSubmit {
                                        addDomain()
                                    }
                                    .onChange(of: newDomain) { _, _ in
                                        domainValidationError = nil
                                    }

                                Button {
                                    addDomain()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(newDomain.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.accentColor)
                                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            if let error = domainValidationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("Blocked Domains (\(domains.count))")
                    } footer: {
                        if isBlocklistActive {
                            Text("New domains will be blocked immediately.")
                                .foregroundStyle(.orange.opacity(0.8))
                        } else {
                            Text("You can paste URLs and they will be cleaned automatically.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Delete Section
                    Section {
                        Button("Delete Blocklist", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                        .disabled(isBlocklistActive && activeBlock?.isLocked == true)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Blocklist")
                .sheet(isPresented: $viewModel.isShowingActivationSheet) {
                    ManualActivationSheet(viewModel: viewModel, blocklistId: blocklistId)
                }
                .alert("Deactivate Block?", isPresented: $isShowingDeactivateConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Deactivate", role: .destructive) {
                        viewModel.deactivateBlocklist(blocklist)
                    }
                } message: {
                    Text("This will immediately unblock all domains in \"\(blocklist.name)\". Are you sure?")
                }
                .alert("Delete Blocklist?", isPresented: $isShowingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        viewModel.deleteBlocklist(blocklist)
                    }
                } message: {
                    Text("Are you sure you want to delete \"\(blocklist.name)\"? This cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "Select a Blocklist",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Choose a blocklist from the list to view details")
                )
            }
        }
        .onChange(of: blocklistId) { _, _ in
            loadBlocklistData()
        }
        .onAppear {
            loadBlocklistData()
        }
    }

    private func loadBlocklistData() {
        if let blocklist {
            name = blocklist.name
            domains = blocklist.domains
            originalDomains = Set(blocklist.domains)
            newDomain = ""
            domainValidationError = nil
        }
    }

    private func addDomain() {
        let cleaned = cleanDomain(newDomain)

        if cleaned.isEmpty {
            domainValidationError = "Please enter a domain"
            return
        }

        if domains.contains(cleaned) {
            domainValidationError = "This domain is already in the list"
            newDomain = ""
            return
        }

        if let validationError = validateDomainFormat(cleaned) {
            domainValidationError = validationError
            return
        }

        domains.append(cleaned)
        newDomain = ""
        domainValidationError = nil
        saveIfValid()
    }

    private func saveIfValid() {
        guard var updated = blocklist else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        // Only save if name is valid and domains exist
        guard !trimmedName.isEmpty, !domains.isEmpty else { return }

        updated.name = trimmedName
        updated.domains = domains
        viewModel.updateBlocklist(updated)
    }

    private func applyPreset(_ preset: BlocklistPreset) {
        // Set name from preset if still default
        if name == "New Blocklist" || name.isEmpty {
            name = preset.rawValue
        }
        // Add all preset domains (avoiding duplicates)
        for domain in preset.domains {
            if !domains.contains(domain) {
                domains.append(domain)
            }
        }
        saveIfValid()
    }

    private func cleanDomain(_ input: String) -> String {
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
        if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
        if let slash = cleaned.firstIndex(of: "/") { cleaned = String(cleaned[..<slash]) }
        return cleaned
    }

    private func validateDomainFormat(_ domain: String) -> String? {
        if domain.contains(" ") {
            return "Domain cannot contain spaces"
        }

        if !domain.contains(".") {
            return "Invalid domain format. Example: youtube.com"
        }

        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        if domain.unicodeScalars.contains(where: { !validCharacters.contains($0) }) {
            return "Domain contains invalid characters"
        }

        if domain.contains("..") {
            return "Domain cannot contain consecutive dots"
        }

        if domain.hasPrefix(".") || domain.hasSuffix(".") {
            return "Domain cannot start or end with a dot"
        }

        if domain.hasPrefix("-") || domain.hasSuffix("-") {
            return "Domain cannot start or end with a hyphen"
        }

        if let lastDot = domain.lastIndex(of: ".") {
            let tld = String(domain[domain.index(after: lastDot)...])
            if tld.count < 2 {
                return "Invalid top-level domain"
            }
        }

        return nil
    }
}

// MARK: - Trigger Summary Row

struct TriggerSummaryRow: View {
    let trigger: TriggerConfig
    let blocklist: BlocklistConfig
    @Bindable var viewModel: WillpowerViewModel

    var body: some View {
        Button {
            navigateToTrigger()
        } label: {
            HStack {
                Image(systemName: trigger.type.icon)
                    .foregroundStyle(trigger.isEnabled ? Color.accentColor : Color.gray)

                VStack(alignment: .leading) {
                    Text(trigger.type.displayName)
                        .font(.subheadline)

                    Text(trigger.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !trigger.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func navigateToTrigger() {
        switch trigger.type {
        case .scheduleBased:
            // Navigate to Schedules and open editor for this schedule
            viewModel.pendingScheduleToEdit = (blocklist: blocklist, trigger: trigger)
            viewModel.selectedCategory = .schedules
            
        case .visitCount:
            // Navigate to Triggers page
            // Note: blocklist visit-count triggers are different from independent triggers
            // Just navigate to the page for now
            viewModel.selectedCategory = .triggers
            
        case .timeBased:
            // Time-based triggers are typically one-off activations, not persistent configs
            // No specific navigation needed
            break
        }
    }
}

// MARK: - TriggerType Extensions

extension TriggerType {
    var icon: String {
        switch self {
        case .timeBased: return "clock"
        case .scheduleBased: return "calendar.badge.clock"
        case .visitCount: return "eye"
        }
    }

    var displayName: String {
        switch self {
        case .timeBased: return "Time-Based"
        case .scheduleBased: return "Scheduled"
        case .visitCount: return "Visit Count"
        }
    }
}

// MARK: - TriggerConfig Summary

extension TriggerConfig {
    var summary: String {
        switch type {
        case .timeBased:
            if let tb = timeBased {
                if let duration = tb.durationSeconds {
                    return formatDuration(duration)
                } else if let endTime = tb.endTime {
                    return "Until \(endTime.formatted(date: .omitted, time: .shortened))"
                }
            }
            return "Not configured"

        case .scheduleBased:
            if let sb = scheduleBased, let window = sb.windows.first {
                return "\(window.timeRangeDescription) \(window.weekdaysDescription)"
            }
            return "Not configured"

        case .visitCount:
            if let vc = visitCount {
                let visitWord = vc.maxVisits == 1 ? "visit" : "visits"
                return "After \(vc.maxVisits) \(visitWord), block for \(formatDuration(vc.blockDurationSeconds))"
            }
            return "Not configured"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
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
}

// MARK: - Independent Trigger Summary Row

struct IndependentTriggerSummaryRow: View {
    let trigger: IndependentTrigger
    @Bindable var viewModel: WillpowerViewModel

    var body: some View {
        Button {
            // Navigate to Triggers page and open editor for this trigger
            viewModel.pendingTriggerToEdit = trigger
            viewModel.selectedCategory = .triggers
        } label: {
            HStack {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .foregroundStyle(trigger.isEnabled ? .orange : .gray)

                VStack(alignment: .leading) {
                    Text(trigger.name)
                        .font(.subheadline)

                    Text(triggerSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !trigger.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var triggerSummary: String {
        let visitWord = trigger.maxVisits == 1 ? "visit" : "visits"
        return "After \(trigger.maxVisits) \(visitWord), block for \(formatDuration(trigger.blockDurationSeconds))"
    }

    private func formatDuration(_ seconds: Int) -> String {
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
}

#Preview {
    let viewModel = WillpowerViewModel()
    let blocklist = BlocklistConfig(
        name: "Social Media",
        domains: ["twitter.com", "facebook.com", "instagram.com"]
    )
    viewModel.blocklists.append(blocklist)
    viewModel.selectedBlocklistId = blocklist.id

    return BlocklistDetailView(
        viewModel: viewModel,
        blocklistId: blocklist.id
    )
}
