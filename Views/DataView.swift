import SwiftUI
import SwiftData
import Photos
import UniformTypeIdentifiers

/// Data & diagnostics: where everything lives, what state the on-device
/// models are in, and how to get your journal OUT (the backup path) and
/// back IN (the restore path). Built from journal cards, not a default
/// Form — the utility tab stays inside the same design language.
struct DataView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DayEntry.date) var entries: [DayEntry]
    @State private var jsonURL: URL?
    @State private var markdownURL: URL?
    @State private var logURL: URL?
    @State private var exportError: String?
    @State private var importMessage: String?
    @State private var showImporter = false
    @State private var showClearLogConfirm = false
    @State private var transcriptionStatus = "Checking…"
    @ObservedObject private var diagnostics = DiagnosticsLog.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Theme.kicker("Data").foregroundStyle(Theme.accentText)
                        Text("Your journal, on this phone.")
                            .font(.caption).foregroundStyle(.secondary)
                        Hairline().padding(.top, 4)
                    }

                    DataSection("Storage") {
                        DataRow("Journal entries", "\(entries.count)")
                        if let first = entries.first, let last = entries.last {
                            DataRow("Range", "\(first.date.formatted(date: .abbreviated, time: .omitted)) – \(last.date.formatted(date: .abbreviated, time: .omitted))")
                        }
                        DataRow("Database", "On-device (SwiftData, v1)")
                        DataRow("Photos & videos", "Photos library (referenced, not copied)")
                        DataRow("Library access", libraryAccessText())
                        DataRow("Cloud database", "None")
                    }

                    DataSection("On-device models") {
                        DataRow("Polish model", ModelAvailability.foundationModelsStatus())
                        DataRow("Transcription", transcriptionStatus)
                        DataRow("Photo analysis", "Vision (on-device)")
                    }

                    DataSection("Export / backup") {
                        Text("The app's data lives in its sandbox on this phone. If the app is deleted, the journal goes with it — export regularly and save the file to iCloud Drive or Files.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Prepare JSON export") {
                            do {
                                let data = try JournalExporter.jsonData(entries: Array(entries))
                                jsonURL = JournalExporter.writeTempFile(data: data, name: "dayline-journal.json")
                                exportError = jsonURL == nil ? "Could not write the export file." : nil
                            } catch {
                                exportError = "Export failed: \(error.localizedDescription)"
                            }
                        }
                        .buttonStyle(.bordered).tint(Theme.ink)
                        if let jsonURL {
                            ShareLink(item: jsonURL) { Label("Share JSON", systemImage: "square.and.arrow.up") }
                        }
                        Button("Prepare readable export (.md)") {
                            let md = JournalExporter.markdown(entries: Array(entries))
                            markdownURL = JournalExporter.writeTempFile(data: Data(md.utf8), name: "dayline-journal.md")
                            exportError = markdownURL == nil ? "Could not write the export file." : nil
                        }
                        .buttonStyle(.bordered).tint(Theme.ink)
                        if let markdownURL {
                            ShareLink(item: markdownURL) { Label("Share Markdown", systemImage: "doc.text") }
                        }
                        if let exportError {
                            Text(exportError).font(.caption).foregroundStyle(.red)
                        }
                    }

                    DataSection("Import / restore") {
                        Text("Restore from a JSON export made by this app. Matching is by entry id, then by day — re-importing the same file updates entries instead of duplicating them.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Import a JSON backup…") { showImporter = true }
                            .buttonStyle(.bordered).tint(Theme.ink)
                        if let importMessage {
                            Text(importMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    DataSection("Diagnostics log") {
                        Text("Decision points from speech, photos, vision, polish and saving — kept on-device across launches. If something misbehaves on your phone, share this log back and the failure will be in it.")
                            .font(.caption).foregroundStyle(.secondary)
                        if diagnostics.lines.isEmpty {
                            Text("No events yet — record and polish an entry first.").font(.caption)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(diagnostics.lines.suffix(15).reversed().enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                }
                            }
                            Button("Prepare log file") {
                                logURL = JournalExporter.writeTempFile(data: Data(diagnostics.exportText().utf8), name: "dayline-diagnostics.txt")
                            }
                            .buttonStyle(.bordered).tint(Theme.ink)
                            if let logURL {
                                ShareLink(item: logURL) { Label("Share log", systemImage: "square.and.arrow.up") }
                            }
                            Button("Clear log", role: .destructive) { showClearLogConfirm = true }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.paper)
            .navigationTitle("Data")
            .task {
                transcriptionStatus = await SpeechTranscriberService.availabilitySummary()
            }
            // A prepared file is a snapshot: clear it when the data it
            // came from changes, so a Share never hands out stale data.
            .onChange(of: entries.count) { _, _ in
                jsonURL = nil
                markdownURL = nil
            }
            .onChange(of: diagnostics.lines.count) { _, _ in
                logURL = nil
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let data = try Data(contentsOf: url)
                        let count = try JournalImporter.importJSON(data, into: modelContext)
                        importMessage = "Imported \(count) entr\(count == 1 ? "y" : "ies") from the backup."
                    } catch {
                        importMessage = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            }
            .confirmationDialog("Clear the diagnostics log?", isPresented: $showClearLogConfirm, titleVisibility: .visible) {
                Button("Clear log", role: .destructive) { diagnostics.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This erases the on-device decision log. Your journal entries are not affected.")
            }
        }
    }

    private func libraryAccessText() -> String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "Full access"
        case .limited: return "Limited — only chosen photos"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }
}

private struct DataSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.kicker(title).foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .journalCard()
    }
}

private struct DataRow: View {
    var label: String
    var value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.ink)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
