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
    let blocklist: BlocklistConfig
    /// Existing trigger to edit (nil for new trigger)
    let existingTrigger: TriggerConfig?

    @Environment(\.dismiss) private var dismiss

    @State private var urlPatterns: [URLPattern] = []
    @State private var maxVisits: Int = 5
    @State private var blockDurationMinutes: Int = 60
    @State private var resetIntervalHours: Int? = nil

    @State private var newPattern: String = ""
    @State private var newPatternIsRegex: Bool = false

    var isEditing: Bool { existingTrigger != nil }

    /// Check if this trigger has caused an active block right now
    var isTriggerActive: Bool {
        guard existingTrigger != nil else { return false }
        return viewModel.activeBlocks.contains {
            $0.blocklistId == blocklist.id &&
            $0.reason == .visitCountTrigger &&
            !$0.isExpired
        }
    }

    init(viewModel: WillpowerViewModel, blocklist: BlocklistConfig, existingTrigger: TriggerConfig? = nil) {
        self.viewModel = viewModel
        self.blocklist = blocklist
        self.existingTrigger = existingTrigger
    }

    var body: some View {
        NavigationStack {
            Form {
                // Blocklist Info
                Section("Blocklist") {
                    LabeledContent("Name", value: blocklist.name)
                    LabeledContent("Domains", value: "\(blocklist.domains.count)")
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
                                Text("This blocklist was activated by this trigger. Changes will take effect after the block expires.")
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
                                    Text("→ blocks \(pattern.associatedDomain)")
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

                    // Add new pattern
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("URL pattern (e.g., youtube.com/shorts)", text: $newPattern)
                            .textFieldStyle(.plain)
                            .onSubmit { addPattern() }

                        HStack {
                            Toggle("Use Regex", isOn: $newPatternIsRegex)
                                .toggleStyle(.checkbox)

                            Spacer()

                            Button("Add Pattern") {
                                addPattern()
                            }
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

                    Picker("Reset Counter After", selection: $resetIntervalHours) {
                        Text("Never").tag(nil as Int?)
                        Text("1 hour").tag(1 as Int?)
                        Text("6 hours").tag(6 as Int?)
                        Text("12 hours").tag(12 as Int?)
                        Text("24 hours").tag(24 as Int?)
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

                        Text("When you visit URLs matching these patterns \(maxVisits) time\(maxVisits == 1 ? "" : "s"), the blocklist \"\(blocklist.name)\" will automatically activate for \(formatDuration(blockDurationMinutes * 60)).")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if let resetHours = resetIntervalHours {
                            Text("The visit counter will reset after \(resetHours) hour\(resetHours == 1 ? "" : "s") of not visiting.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
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
                    .disabled(urlPatterns.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 550)
        .onAppear {
            if let trigger = existingTrigger, let vc = trigger.visitCount {
                urlPatterns = vc.urlPatterns
                maxVisits = vc.maxVisits
                blockDurationMinutes = vc.blockDurationSeconds / 60
                resetIntervalHours = vc.resetIntervalSeconds.map { $0 / 3600 }
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
            associatedDomain: domain
        )

        urlPatterns.append(pattern)
        newPattern = ""
        newPatternIsRegex = false
    }

    private func saveTrigger() {
        let trigger = VisitCountTrigger(
            urlPatterns: urlPatterns,
            maxVisits: maxVisits,
            blockDurationSeconds: blockDurationMinutes * 60,
            resetIntervalSeconds: resetIntervalHours.map { $0 * 3600 }
        )

        if let existingTrigger {
            viewModel.updateVisitTrigger(triggerId: existingTrigger.id, in: blocklist, newTrigger: trigger)
        } else {
            viewModel.addVisitTrigger(to: blocklist, trigger: trigger)
        }
        dismiss()
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
    TriggerEditorSheet(
        viewModel: WillpowerViewModel(),
        blocklist: BlocklistConfig(name: "Social Media", domains: ["youtube.com"])
    )
}
