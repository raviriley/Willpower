//
//  TriggerEditorSheet.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct TriggerEditorSheet: View {
    @Bindable var viewModel: WillpowerViewModel
    /// Existing trigger to edit (nil for new trigger)
    let existingTrigger: IndependentTrigger?

    @Environment(\.dismiss) private var dismiss

    @State private var triggerName: String = ""
    @State private var urlPatterns: [URLPattern] = []
    @State private var maxVisits: Int = 5
    @State private var blockDurationMinutes: Int = 60

    @State private var newPattern: String = ""
    @State private var newPatternIsRegex: Bool = false
    @State private var newPatternBlockAction: BlockAction = .blockDomain
    @State private var newPatternBlocklistId: UUID?

    var isEditing: Bool { existingTrigger != nil }

    /// Check if this trigger has caused an active block right now
    var isTriggerActive: Bool {
        guard let trigger = existingTrigger else { return false }
        for pattern in trigger.urlPatterns {
            if viewModel.activeBlocks.contains(where: { $0.blocklistId == pattern.id && !$0.isExpired }) {
                return true
            }
        }
        return false
    }

    init(viewModel: WillpowerViewModel, existingTrigger: IndependentTrigger? = nil) {
        self.viewModel = viewModel
        self.existingTrigger = existingTrigger
    }

    var body: some View {
        NavigationStack {
            Form {
                // Trigger Name
                Section("Trigger Name") {
                    TextField("Name (e.g., Social Media Limit)", text: $triggerName)
                }

                // Active trigger warning
                if isTriggerActive {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Trigger is Currently Active")
                                    .font(.headline)
                                Text("This trigger has been activated. Changes will take effect after the block expires.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
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
                        TextField("URL pattern (e.g., youtube.com/shorts)", text: $newPattern)
                            .textFieldStyle(.plain)
                            .onSubmit { addPattern() }

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

                        Button("Add Pattern") {
                            addPattern()
                        }
                        .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
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

                        Text("Each pattern independently blocks its domain or activate a blocklist.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Trigger" : "New Visit Trigger")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveTrigger()
                    }
                    .disabled(urlPatterns.isEmpty || triggerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 550)
        .onAppear {
            if let trigger = existingTrigger {
                triggerName = trigger.name
                urlPatterns = trigger.urlPatterns
                maxVisits = trigger.maxVisits
                blockDurationMinutes = trigger.blockDurationSeconds / 60
            }
        }
    }

    private func addPattern() {
        let trimmed = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let domain = extractDomain(from: trimmed)
        let pattern = URLPattern(
            pattern: trimmed,
            isRegex: newPatternIsRegex,
            associatedDomain: domain,
            blockAction: newPatternBlockAction
        )

        urlPatterns.append(pattern)
        newPattern = ""
        newPatternIsRegex = false
        newPatternBlockAction = .blockDomain
    }

    private func saveTrigger() {
        let name = triggerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if let existingTrigger {
            // Update existing trigger
            var updated = existingTrigger
            updated.name = name
            updated.urlPatterns = urlPatterns
            updated.maxVisits = maxVisits
            updated.blockDurationSeconds = blockDurationMinutes * 60
            viewModel.updateIndependentTrigger(updated)
        } else {
            // Create new trigger
            let trigger = IndependentTrigger(
                name: name,
                urlPatterns: urlPatterns,
                maxVisits: maxVisits,
                blockDurationSeconds: blockDurationMinutes * 60
            )
            viewModel.createIndependentTrigger(trigger)
        }
        dismiss()
    }

    private func blockActionDescription(for pattern: URLPattern) -> String {
        switch pattern.blockAction {
        case .blockDomain:
            return "→ blocks \(pattern.associatedDomain)"
        case .activateBlocklist(let blocklistId):
            if let blocklist = viewModel.blocklists.first(where: { $0.id == blocklistId }) {
                return "→ activates \(blocklist.name) blocklist"
            }
            return "→ activates blocklist"
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
    TriggerEditorSheet(viewModel: WillpowerViewModel())
}
