//
//  AllowlistDetailView.swift
//  Willpower
//
//  Created by Ravi Riley on 2/16/26.
//

import SwiftUI
import WillpowerKit

// MARK: - Allow List Presets

enum AllowlistPreset: String, CaseIterable, Identifiable {
    case workFocus = "Work Focus"
    case studyMode = "Study Mode"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .workFocus: return "briefcase"
        case .studyMode: return "book"
        }
    }

    var domains: [String] {
        switch self {
        case .workFocus:
            return [
                "google.com", "gmail.com", "github.com", "stackoverflow.com",
                "slack.com", "notion.com", "linear.app", "figma.com"
            ]
        case .studyMode:
            return [
                "google.com", "wikipedia.org",
                "khanacademy.org", "coursera.org", "wolframalpha.com"
            ]
        }
    }

    var description: String {
        switch self {
        case .workFocus:
            return "Productivity apps and tools"
        case .studyMode:
            return "Educational resources"
        }
    }
}

// MARK: - AllowlistDetailView

struct AllowlistDetailView: View {
    @Bindable var viewModel: WillpowerViewModel
    let allowlistId: UUID

    @State private var isShowingDeactivateConfirmation = false
    @State private var isShowingDeleteConfirmation = false

    // Inline editing state
    @State private var name: String = ""
    @State private var domains: [String] = []
    @State private var newDomain: String = ""
    @State private var domainValidationError: String?
    @State private var originalDomains: Set<String> = []

    /// Get the current allow list from viewModel (always fresh)
    var allowlist: BlocklistConfig? {
        viewModel.blocklists.first { $0.id == allowlistId }
    }

    var activeBlock: ActiveBlock? {
        guard let allowlist else { return nil }
        return viewModel.activeBlock(for: allowlist)
    }

    var isAllowlistActive: Bool {
        activeBlock != nil
    }

    /// Check if a domain can be deleted (only new domains when active)
    func canDeleteDomain(_ domain: String) -> Bool {
        if !isAllowlistActive { return true }
        return !originalDomains.contains(domain)
    }

    /// Independent triggers that target this allow list
    var targetingTriggers: [IndependentTrigger] {
        guard let allowlist else { return [] }
        return viewModel.independentTriggers.filter { trigger in
            trigger.urlPatterns.contains { pattern in
                if case .activateBlocklist(let targetId) = pattern.blockAction {
                    return targetId == allowlist.id
                }
                return false
            }
        }
    }

    var body: some View {
        Group {
            if let allowlist {
                Form {
                    // Name Section
                    Section("Name") {
                        TextField("Allow List Name", text: $name)
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
                                            color: activeBlock.isLocked ? .green : .mint
                                        )
                                        StatusBadge(text: "ALLOW LIST", color: .green)
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
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)

                            if activeBlock.isLocked {
                                Label {
                                    Text("This allow list cannot be deactivated until it expires")
                                        .font(.callout)
                                } icon: {
                                    Image(systemName: "info.circle")
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Button("Deactivate Allow List", role: .destructive) {
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
                                    Text("Only the listed domains will be accessible when active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)

                            Button {
                                viewModel.isShowingAllowlistActivationSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.shield.fill")
                                    Text("Activate Now")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.large)
                            .disabled(domains.isEmpty)
                        }
                    }

                    // Triggers Section
                    Section {
                        if allowlist.triggers.isEmpty && targetingTriggers.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "bolt.slash")
                                        .foregroundStyle(.secondary)
                                    Text("No triggers configured")
                                        .foregroundStyle(.secondary)
                                }
                                Text("Triggers automatically activate this allow list based on schedules or visit counts.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        } else {
                            // Embedded triggers (schedules, etc.)
                            ForEach(allowlist.triggers) { trigger in
                                TriggerSummaryRow(
                                    trigger: trigger,
                                    blocklist: allowlist,
                                    viewModel: viewModel
                                )
                            }

                            // Independent triggers that target this allow list
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

                    // Active allow list info banner
                    if isAllowlistActive {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Allow List is Active")
                                        .font(.headline)
                                    Text("You can add new domains but cannot remove existing ones until it expires.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Preset templates (only show when no domains yet)
                    if domains.isEmpty && !isAllowlistActive {
                        Section("Start from Template") {
                            ForEach(AllowlistPreset.allCases) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    HStack {
                                        Image(systemName: preset.icon)
                                            .foregroundStyle(.green)
                                            .frame(width: 24)
                                        VStack(alignment: .leading) {
                                            Text(preset.rawValue)
                                                .foregroundStyle(.primary)
                                            Text("\(preset.domains.count) sites - \(preset.description)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(.green)
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
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                        .help("Cannot remove while allow list is active")
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
                                .foregroundStyle(newDomain.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : .green)
                                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            if let error = domainValidationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    } header: {
                        Text("Allowed Domains (\(domains.count))")
                    } footer: {
                        Text("Only these domains will be accessible. All other websites will be blocked.")
                            .foregroundStyle(.secondary)
                    }

                    // Delete Section
                    Section {
                        Button("Delete Allow List", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                        .disabled(isAllowlistActive && activeBlock?.isLocked == true)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Allow List")
                .sheet(isPresented: $viewModel.isShowingAllowlistActivationSheet) {
                    AllowlistActivationSheet(viewModel: viewModel, allowlistId: allowlistId)
                }
                .alert("Deactivate Allow List?", isPresented: $isShowingDeactivateConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Deactivate", role: .destructive) {
                        viewModel.deactivateBlocklist(allowlist)
                    }
                } message: {
                    Text("This will restore normal browsing. All websites will become accessible again.")
                }
                .alert("Delete Allow List?", isPresented: $isShowingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        viewModel.deleteBlocklist(allowlist)
                    }
                } message: {
                    Text("Are you sure you want to delete \"\(allowlist.name)\"? This cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "Select an Allow List",
                    systemImage: "checkmark.shield",
                    description: Text("Choose an allow list from the list to view details")
                )
            }
        }
        .onChange(of: allowlistId) { _, _ in
            loadAllowlistData()
        }
        .onAppear {
            loadAllowlistData()
        }
    }

    private func loadAllowlistData() {
        if let allowlist {
            name = allowlist.name
            domains = allowlist.domains
            originalDomains = Set(allowlist.domains)
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
        guard var updated = allowlist else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        guard !trimmedName.isEmpty else { return }

        updated.name = trimmedName
        updated.domains = domains
        viewModel.updateBlocklist(updated)
    }

    private func applyPreset(_ preset: AllowlistPreset) {
        if name == "New Allow List" || name.isEmpty {
            name = preset.rawValue
        }
        for domain in preset.domains {
            if !domains.contains(domain) {
                domains.append(domain)
            }
        }
        saveIfValid()
    }

    private func validateDomainFormat(_ domain: String) -> String? {
        if domain.contains(" ") {
            return "Domain cannot contain spaces"
        }

        if !domain.contains(".") {
            return "Invalid domain format. Example: google.com"
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

#Preview {
    let viewModel = WillpowerViewModel()
    let allowlist = BlocklistConfig(
        name: "Work Focus",
        domains: ["google.com", "github.com", "stackoverflow.com"],
        mode: .allow
    )
    viewModel.blocklists.append(allowlist)
    viewModel.selectedAllowlistId = allowlist.id

    return AllowlistDetailView(
        viewModel: viewModel,
        allowlistId: allowlist.id
    )
}
