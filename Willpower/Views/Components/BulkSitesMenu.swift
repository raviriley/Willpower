//
//  BulkSitesMenu.swift
//  Willpower
//
//  Bulk site entry, shared by the blocklist and allowlist editors: paste many
//  at once, import a text/CSV/hosts file, or export the current list.
//
//  Parsing lives in WillpowerKit (DomainBulkParsing) so these paths accept
//  exactly what the single-domain field accepts, and nothing more.
//

import SwiftUI
import UniformTypeIdentifiers
import WillpowerKit

// MARK: - Bulk paste sheet

struct BulkAddSitesSheet: View {
    /// Domains already in the list, so we can report how many are genuinely new.
    let existingDomains: [String]
    /// Called with the parsed, de-duplicated domains the user chose to add.
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    private var parsed: [String] {
        DomainBulkParsing.parseDomains(fromPastedText: text)
    }

    private var newDomains: [String] {
        let existing = Set(existingDomains)
        return parsed.filter { !existing.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Sites in Bulk")
                .font(.headline)

            Text("Paste sites below — one per line, or separated by commas. Full URLs are fine, and `#` comments and hosts-file lines are handled.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 420, minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )

            // Live feedback, so an empty result is explainable before committing
            HStack(spacing: 4) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing pasted yet.")
                        .foregroundStyle(.secondary)
                } else if parsed.isEmpty {
                    Label("No recognizable sites found", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    let duplicates = parsed.count - newDomains.count
                    Text("\(newDomains.count) to add")
                        .foregroundStyle(newDomains.isEmpty ? Color.orange : Color.green)
                    if duplicates > 0 {
                        Text("· \(duplicates) already in list")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Sites") {
                    onAdd(newDomains)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newDomains.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }
}

// MARK: - Exported document

/// Plain-text wrapper so `.fileExporter` can write the list out.
struct DomainListDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(domains: [String]) {
        self.text = DomainBulkParsing.exportText(for: domains)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: - The menu itself

struct BulkSitesMenu: View {
    let domains: [String]
    /// Suggested filename stem for export, e.g. the list's name.
    let listName: String
    /// True when the list can't currently be added to (e.g. an active block).
    let isAddDisabled: Bool
    let onAdd: ([String]) -> Void

    @State private var isShowingPasteSheet = false
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var importError: String?

    private var exportFilename: String {
        let stem = listName.trimmingCharacters(in: .whitespaces)
        return stem.isEmpty ? "Willpower Sites" : stem
    }

    var body: some View {
        Menu {
            Button("Paste Multiple Sites…") { isShowingPasteSheet = true }
                .disabled(isAddDisabled)
            Button("Import from File…") { isImporting = true }
                .disabled(isAddDisabled)
            Divider()
            Button("Export to File…") { isExporting = true }
                .disabled(domains.isEmpty)
        } label: {
            Image(systemName: "square.and.arrow.down.on.square")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Add or export many sites at once")

        .sheet(isPresented: $isShowingPasteSheet) {
            BulkAddSitesSheet(existingDomains: domains, onAdd: onAdd)
        }

        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.plainText, .commaSeparatedText, .text, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }

        .fileExporter(
            isPresented: $isExporting,
            document: DomainListDocument(domains: domains),
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { _ in }

        .alert("Couldn't import that file",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription

        case .success(let urls):
            guard let url = urls.first else { return }

            // the panel hands back a security-scoped URL; we must open it explicitly
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                importError = "The file could not be read."
                return
            }

            let text = String(decoding: data, as: UTF8.self)
            let existing = Set(domains)
            let toAdd = DomainBulkParsing.parseDomains(fromPastedText: text)
                .filter { !existing.contains($0) }

            if toAdd.isEmpty {
                importError = "No new sites were found in that file."
                return
            }

            onAdd(toAdd)
        }
    }
}
