//
//  TriggerDetailView.swift
//  Willpower
//
//  Created by Ravi Riley on 1/2/26.
//

import SwiftUI
import WillpowerKit

struct TriggerDetailView: View {
    @Bindable var viewModel: WillpowerViewModel

    @State private var triggerName: String = ""
    @State private var urlPatterns: [URLPattern] = []
    @State private var maxVisits: Int = 5
    @State private var blockDurationMinutes: Int = 60

    @State private var newPattern: String = ""
    @State private var newPatternIsRegex: Bool = false
    @State private var newPatternBlockAction: BlockAction = .blockDomain
    @State private var patternValidationError: String?

    @State private var isShowingDeleteConfirmation = false

    /// Get the current trigger from viewModel (always fresh)
    var trigger: IndependentTrigger? {
        viewModel.selectedTrigger
    }

    /// Check if this trigger has caused an active block right now
    var isTriggerActive: Bool {
        guard let trigger else { return false }
        for pattern in trigger.urlPatterns {
            if viewModel.activeBlocks.contains(where: { $0.blocklistId == pattern.id && !$0.isExpired }) {
                return true
            }
        }
        return false
    }

    /// Total visits for this trigger
    var totalVisits: Int {
        guard let trigger else { return 0 }
        return trigger.urlPatterns.reduce(0) { sum, pattern in
            if let record = viewModel.visitRecords.first(where: { $0.patternId == pattern.id }) {
                return sum + record.visitCount
            }
            return sum
        }
    }

    var body: some View {
        Group {
            if let trigger {
                Form {
                    // Trigger Name
                    Section("Trigger Name") {
                        TextField("Name (e.g., Social Media Limit)", text: $triggerName)
                    }

                    // Status Section
                    Section("Status") {
                        HStack {
                            Text("Visit Count")
                            Spacer()
                            Text("\(totalVisits)/\(maxVisits)")
                                .foregroundStyle(visitCountColor)
                        }

                        if isTriggerActive {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Trigger is Active")
                                        .font(.headline)
                                    Text("This trigger has been activated. Changes will take effect after the block expires.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button("Reset Visit Count") {
                            let patternIds = trigger.urlPatterns.map { $0.id }
                            viewModel.resetVisitCounts(patternIds: patternIds)
                        }
                        .disabled(!viewModel.isDaemonRunning)
                    }

                    // URL Patterns Section
                    Section("URL Patterns to Monitor") {
                        ForEach(urlPatterns) { pattern in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pattern.pattern)
                                            .font(.system(.body, design: .monospaced))
                                        HStack(spacing: 8) {
                                            Text(pattern.isRegex ? "Regex" : "Contains")
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.2))
                                                .clipShape(Capsule())
                                            Text(blockActionDescription(for: pattern))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        urlPatterns.removeAll { $0.id == pattern.id }
                                        saveIfValid()
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Add new pattern
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("youtube.com/shorts", text: $newPattern)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .onSubmit { addPattern() }
                                .onChange(of: newPattern) { _, _ in
                                    patternValidationError = nil
                                }

                            if let error = patternValidationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            HStack {
                                Toggle("Use Regex", isOn: $newPatternIsRegex)
                                    .toggleStyle(.checkbox)

                                Spacer()
                            }

                            // Block Action Picker
                            Picker("When triggered", selection: $newPatternBlockAction) {
                                Text("Block domain").tag(BlockAction.blockDomain)
                                ForEach(viewModel.blocklists) { blocklist in
                                    Text("Activate: \(blocklist.name)").tag(BlockAction.activateBlocklist(blocklistId: blocklist.id))
                                }
                            }
                            .pickerStyle(.menu)

                            HStack {
                                Spacer()
                                Button {
                                    addPattern()
                                } label: {
                                    Label("Add Pattern", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    // Threshold Settings
                    Section("Trigger Settings") {
                        Stepper("Max Visits: \(maxVisits)", value: $maxVisits, in: 1...100)

                        Picker("Block Duration", selection: $blockDurationMinutes) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("4 hours").tag(240)
                            Text("8 hours").tag(480)
                            Text("24 hours").tag(1440)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label {
                                Text("How it works")
                                    .font(.headline)
                            } icon: {
                                Image(systemName: "info.circle")
                            }

                            Text("When you visit URLs matching these patterns \(maxVisits) time\(maxVisits == 1 ? "" : "s"), blocking will activate for \(formatDuration(blockDurationMinutes * 60)).")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            Text("Each pattern independently blocks its domain or activates a blocklist.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Delete Section
                    Section {
                        Button("Delete Trigger", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Trigger")
                .onChange(of: triggerName) { _, _ in saveIfValid() }
                .onChange(of: maxVisits) { _, _ in saveIfValid() }
                .onChange(of: blockDurationMinutes) { _, _ in saveIfValid() }
                .alert("Delete Trigger?", isPresented: $isShowingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        deleteTrigger()
                    }
                } message: {
                    Text("Are you sure you want to delete this trigger? This will also delete all visit history. This cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "Select a Trigger",
                    systemImage: "eye.trianglebadge.exclamationmark",
                    description: Text("Choose a trigger to view or edit")
                )
            }
        }
        .onChange(of: viewModel.selectedTriggerId) { _, _ in
            loadTriggerData()
        }
        .onAppear {
            loadTriggerData()
        }
    }

    private var visitCountColor: Color {
        let ratio = Double(totalVisits) / Double(maxVisits)
        if ratio >= 1.0 {
            return .red
        } else if ratio >= 0.7 {
            return .orange
        } else if ratio >= 0.4 {
            return .yellow
        } else {
            return .green
        }
    }

    private func loadTriggerData() {
        if let trigger {
            triggerName = trigger.name
            urlPatterns = trigger.urlPatterns
            maxVisits = trigger.maxVisits
            blockDurationMinutes = trigger.blockDurationSeconds / 60
            newPattern = ""
            newPatternIsRegex = false
            newPatternBlockAction = .blockDomain
            patternValidationError = nil
        }
    }

    private func addPattern() {
        let cleaned = cleanURLPattern(newPattern)

        // Validate the cleaned pattern
        if cleaned.isEmpty {
            patternValidationError = "Please enter a URL pattern"
            return
        }

        // Check for duplicates
        if urlPatterns.contains(where: { $0.pattern == cleaned }) {
            patternValidationError = "This pattern is already in the list"
            newPattern = ""
            return
        }

        // Validate pattern format (skip validation for regex patterns)
        if !newPatternIsRegex, let validationError = validateURLPattern(cleaned) {
            patternValidationError = validationError
            return
        }

        let domain = extractDomain(from: cleaned)
        let pattern = URLPattern(
            pattern: cleaned,
            isRegex: newPatternIsRegex,
            associatedDomain: domain,
            blockAction: newPatternBlockAction
        )

        urlPatterns.append(pattern)
        newPattern = ""
        newPatternIsRegex = false
        newPatternBlockAction = .blockDomain
        patternValidationError = nil
        saveIfValid()
    }

    private func saveIfValid() {
        guard let existingTrigger = trigger else { return }

        let name = triggerName.trimmingCharacters(in: .whitespaces)
        // Only save if name is valid and patterns exist
        guard !name.isEmpty, !urlPatterns.isEmpty else { return }

        var updated = existingTrigger
        updated.name = name
        updated.urlPatterns = urlPatterns
        updated.maxVisits = maxVisits
        updated.blockDurationSeconds = blockDurationMinutes * 60

        viewModel.updateIndependentTrigger(updated)
    }

    private func deleteTrigger() {
        guard let trigger else { return }
        viewModel.deleteIndependentTrigger(trigger)
        viewModel.selectedTriggerId = nil
    }

    private func blockActionDescription(for pattern: URLPattern) -> String {
        switch pattern.blockAction {
        case .blockDomain:
            return "\u{2192} blocks \(pattern.associatedDomain)"
        case .activateBlocklist(let blocklistId):
            if let blocklist = viewModel.blocklists.first(where: { $0.id == blocklistId }) {
                return "\u{2192} activates \(blocklist.name) blocklist"
            }
            return "\u{2192} activates blocklist"
        }
    }

    private func extractDomain(from pattern: String) -> String {
        var domain = pattern.lowercased()
        if domain.hasPrefix("http://") { domain = String(domain.dropFirst(7)) }
        if domain.hasPrefix("https://") { domain = String(domain.dropFirst(8)) }
        if domain.hasPrefix("www.") { domain = String(domain.dropFirst(4)) }
        if let slash = domain.firstIndex(of: "/") { domain = String(domain[..<slash]) }
        return domain
    }

    private func cleanURLPattern(_ input: String) -> String {
        var cleaned = input.lowercased().trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("http://") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("https://") { cleaned = String(cleaned.dropFirst(8)) }
        if cleaned.hasPrefix("www.") { cleaned = String(cleaned.dropFirst(4)) }
        return cleaned
    }

    private func validateURLPattern(_ pattern: String) -> String? {
        if pattern.contains(" ") {
            return "URL pattern cannot contain spaces"
        }

        let domainPart: String
        if let slash = pattern.firstIndex(of: "/") {
            domainPart = String(pattern[..<slash])
        } else {
            domainPart = pattern
        }

        if !domainPart.contains(".") {
            return "Invalid URL pattern. Example: youtube.com/shorts"
        }

        let validDomainCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        if domainPart.unicodeScalars.contains(where: { !validDomainCharacters.contains($0) }) {
            return "Domain contains invalid characters"
        }

        if domainPart.contains("..") {
            return "Domain cannot contain consecutive dots"
        }

        if domainPart.hasPrefix(".") || domainPart.hasSuffix(".") {
            return "Domain cannot start or end with a dot"
        }

        if domainPart.hasPrefix("-") || domainPart.hasSuffix("-") {
            return "Domain cannot start or end with a hyphen"
        }

        if let lastDot = domainPart.lastIndex(of: ".") {
            let tld = String(domainPart[domainPart.index(after: lastDot)...])
            if tld.count < 2 {
                return "Invalid top-level domain"
            }
        }

        return nil
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
    TriggerDetailView(viewModel: WillpowerViewModel())
}
