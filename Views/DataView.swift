import SwiftUI
import SwiftData

/// Data & diagnostics: where everything lives, what state the on-device
/// models are in, and how to get your journal OUT (the backup path).
struct DataView: View {
    @Query(sort: \DayEntry.date) var entries: [DayEntry]
    @State private var jsonURL: URL?
    @State private var markdownURL: URL?

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
                Section("Logs") {
                    Text("Runtime logs go to Apple's unified log (subsystem com.steenjennings.dayline). View them live in Xcode's console while the app runs from your Mac, or in Console.app. Build/test logs live in GitHub Actions on each push.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Data")
        }
    }
}
