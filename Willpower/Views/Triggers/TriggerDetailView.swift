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
    @State private var newPatternDomain: String = ""  // Domain to block (required for regex)
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
            if trigger != nil {
                Form {
                    // Trigger Name
                    Section("Trigger Name") {
                        TextField("", text: $triggerName, prompt: Text("Limit Doomscrolling"))
                    }

                    // Status Section
                    Section("Status") {
                        HStack {
                            Text("Visit Count")
                            Spacer()
                            Text("\(totalVisits)/\(maxVisits)")
                                .foregroundStyle(visitCountColor(current: totalVisits, max: maxVisits))
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
                    }

                    // Trigger Settings
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

                    // URL Patterns Section
                    Section("URL Patterns to Monitor") {
                        ForEach(urlPatterns) { pattern in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("When you visit a URL \(maxVisits) time\(maxVisits == 1 ? "" : "s") that \(pattern.isRegex ? "matches regex" : "contains"):")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(pattern.pattern)
                                        .font(.system(.body, design: .monospaced))
                                    Text(blockActionDescription(for: pattern))
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    urlPatterns.removeAll { $0.id == pattern.id }
                                    saveIfValid()
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }

                        // Add new pattern
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pattern")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("", text: $newPattern, prompt: Text(newPatternIsRegex ? "(?:twitter\\.com|x\\.com)/[^/]+/status/\\d+" : "youtube.com/shorts"))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .onSubmit { addPattern() }
                                        .onChange(of: newPattern) { _, _ in
                                            patternValidationError = nil
                                        }

                                    Button {
                                        addPattern()
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(newPattern.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.blue)
                                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }

                            Toggle(isOn: $newPatternIsRegex) {
                                Text("Use Regex")
                            }
                            .toggleStyle(.checkbox)

                            // Show domain field when regex is enabled (can't auto-extract from regex)
                            if newPatternIsRegex {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Domain to block")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("", text: $newPatternDomain, prompt: Text("twitter.com"))
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }

                            if let error = patternValidationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Picker("When triggered", selection: $newPatternBlockAction) {
                                Text("Block domain").tag(BlockAction.blockDomain)
                                ForEach(viewModel.blocklists) { blocklist in
                                    Text("Activate: \(blocklist.name)").tag(BlockAction.activateBlocklist(blocklistId: blocklist.id))
                                }
                            }
                            .pickerStyle(.menu)
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
        // For regex, don't clean (preserve regex syntax); for simple patterns, clean
        let patternString = newPatternIsRegex ? newPattern.trimmingCharacters(in: .whitespaces) : cleanURLPattern(newPattern)

        // Validate the pattern
        if patternString.isEmpty {
            patternValidationError = "Please enter a URL pattern"
            return
        }

        // For regex patterns, require manual domain entry
        if newPatternIsRegex {
            let cleanedDomain = cleanURLPattern(newPatternDomain)
            if cleanedDomain.isEmpty {
                patternValidationError = "Please enter the domain to block"
                return
            }
        }

        // Check for duplicates
        if urlPatterns.contains(where: { $0.pattern == patternString }) {
            patternValidationError = "This pattern is already in the list"
            newPattern = ""
            return
        }

        // Validate pattern format (skip validation for regex patterns)
        if !newPatternIsRegex, let validationError = validateURLPattern(patternString) {
            patternValidationError = validationError
            return
        }

        // For regex, use manually entered domain; for simple patterns, extract from pattern
        let domain = newPatternIsRegex ? cleanURLPattern(newPatternDomain) : extractDomain(from: patternString)
        let pattern = URLPattern(
            pattern: patternString,
            isRegex: newPatternIsRegex,
            associatedDomain: domain,
            blockAction: newPatternBlockAction
        )

        urlPatterns.append(pattern)
        newPattern = ""
        newPatternIsRegex = false
        newPatternDomain = ""
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
        let duration = formatDuration(blockDurationMinutes * 60)
        switch pattern.blockAction {
        case .blockDomain:
            return "→ \(pattern.associatedDomain) is blocked for \(duration)"
        case .activateBlocklist(let blocklistId):
            if let blocklist = viewModel.blocklists.first(where: { $0.id == blocklistId }) {
                return "→ \(blocklist.name) blocklist is activated for \(duration)"
            }
            return "→ blocklist is activated for \(duration)"
        }
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
}

#Preview {
    TriggerDetailView(viewModel: WillpowerViewModel())
}
