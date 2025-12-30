//
//  BlocklistEditorSheet.swift
//  Willpower
//
//  Created by Ravi Riley on 12/29/25.
//

import SwiftUI
import WillpowerKit

struct BlocklistEditorSheet: View {
    @Bindable var viewModel: WillpowerViewModel
    let blocklist: BlocklistConfig?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var domains: [String] = []
    @State private var newDomain: String = ""
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

                    HStack {
                        TextField("Add domain (e.g., youtube.com)", text: $newDomain)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                addDomain()
                            }

                        Button("Add") {
                            addDomain()
                        }
                        .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section {
                    if isBlocklistActive {
                        Text("New domains will be blocked immediately when saved.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Enter domain names without http:// or www. prefix")
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

    private func addDomain() {
        let cleaned = cleanDomain(newDomain)
        guard !cleaned.isEmpty, !domains.contains(cleaned) else {
            newDomain = ""
            return
        }
        domains.append(cleaned)
        newDomain = ""
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
