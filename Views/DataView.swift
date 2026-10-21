import SwiftUI
import SwiftData

/// Data & diagnostics: where everything lives, what state the on-device
/// models are in, and how to get your journal OUT (the backup path).
struct DataView: View {
    @Query(sort: \DayEntry.date) var entries: [DayEntry]
    @State private var jsonURL: URL?
    @State private var markdownURL: URL?
    @State private var logURL: URL?
    @ObservedObject private var diagnostics = DiagnosticsLog.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Storage") {
                    LabeledContent("Journal entries", value: "\(entries.count)")
                    if let first = entries.first, let last = entries.last {
                        LabeledContent("Range", value: "\(first.date.formatted(date: .abbreviated, time: .omitted)) – \(last.date.formatted(date: .abbreviated, time: .omitted))")
                    }
                    LabeledContent("Database", value: "On-device (SwiftData)")
                    LabeledContent("Photos & videos", value: "Photos library (referenced, not copied)")
                    LabeledContent("Cloud database", value: "None")
                }
                Section("On-device models") {
                    LabeledContent("Polish model", value: ModelAvailability.foundationModelsStatus())
                    LabeledContent("Transcription", value: "SpeechAnalyzer (on-device)")
                    LabeledContent("Photo analysis", value: "Vision (on-device)")
                }
                Section("Export / backup") {
                    Text("The app's data lives in its sandbox on this phone. If the app is deleted, the journal goes with it - export regularly and save the file to iCloud Drive or Files.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Prepare JSON export") {
                        if let data = try? JournalExporter.jsonData(entries: Array(entries)) {
                            jsonURL = JournalExporter.writeTempFile(data: data, name: "dayline-journal.json")
                        }
                    }
                    if let jsonURL {
                        ShareLink(item: jsonURL) { Label("Share JSON", systemImage: "square.and.arrow.up") }
                    }
                    Button("Prepare readable export (.md)") {
                        let md = JournalExporter.markdown(entries: Array(entries))
                        markdownURL = JournalExporter.writeTempFile(data: Data(md.utf8), name: "dayline-journal.md")
                    }
                    if let markdownURL {
                        ShareLink(item: markdownURL) { Label("Share Markdown", systemImage: "doc.text") }
                    }
                }
                Section("Diagnostics log") {
                    Text("Decision points from speech, photos, vision, polish and saving - kept on-device across launches. If something misbehaves on your phone, share this log back and the failure will be in it.")
                        .font(.caption).foregroundStyle(.secondary)
                    if diagnostics.lines.isEmpty {
                        Text("No events yet - record and polish an entry first.").font(.caption)
                    } else {
                        ForEach(Array(diagnostics.lines.suffix(15).reversed().enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 9, design: .monospaced)).textSelection(.enabled)
                        }
                        Button("Prepare log file") {
                            logURL = JournalExporter.writeTempFile(data: Data(diagnostics.exportText().utf8), name: "dayline-diagnostics.txt")
                        }
                        if let logURL {
                            ShareLink(item: logURL) { Label("Share log", systemImage: "square.and.arrow.up") }
                        }
                        Button("Clear log", role: .destructive) { diagnostics.clear() }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.paper)
            .navigationTitle("Data")
        }
    }
}
