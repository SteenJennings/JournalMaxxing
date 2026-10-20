import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A Codable snapshot of a DayEntry for export. DayEntry itself is a
/// SwiftData @Model (not Codable), so exports map through this shape.
/// This file is the app's backup format: if the app is ever deleted,
/// a JSON export saved to Files / iCloud Drive is the recovery path.
struct ExportEntry: Codable {
    var date: Date
    var rawTranscript: String
    var polishedText: String
    var mood: String?
    var projectTags: [String]
    var highlightLocalId: String?
    var mediaLocalIds: [String]
    var linkURLs: [String]
    var isFavorite: Bool

    init(_ e: DayEntry) {
        date = e.date
        rawTranscript = e.rawTranscript
        polishedText = e.polishedText
        mood = e.mood
        projectTags = e.projectTags
        highlightLocalId = e.highlightLocalId
        mediaLocalIds = e.mediaLocalIds
        linkURLs = e.linkURLs
        isFavorite = e.isFavorite
    }
}

enum JournalExporter {
    static func jsonData(entries: [DayEntry]) throws -> Data {
        let sorted = entries.sorted { $0.date < $1.date }.map(ExportEntry.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(sorted)
    }

    /// Human-readable backup: one section per day.
    static func markdown(entries: [DayEntry]) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        var out = "# Dayline Journal Export\n"
        for e in entries.sorted(by: { $0.date < $1.date }) {
            out += "\n## \(df.string(from: e.date))\n\n"
            out += (e.polishedText.isEmpty ? e.rawTranscript : e.polishedText) + "\n"
            if !e.projectTags.isEmpty {
                out += "\nTags: " + e.projectTags.map { "#\($0)" }.joined(separator: " ") + "\n"
            }
            if let mood = e.mood { out += "Mood: \(mood)\n" }
            if !e.mediaLocalIds.isEmpty {
                out += "Photos: " + e.mediaLocalIds.joined(separator: ", ") + "\n"
            }
        }
        return out
    }

    static func writeTempFile(data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// Human-readable Foundation Models availability for the Data tab - the
/// single most useful diagnostic for "why did polish fall back?".
enum ModelAvailability {
    static func foundationModelsStatus() -> String {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return "Available (on-device)"
        case .unavailable(.deviceNotEligible):
            return "Unavailable - device not eligible for Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Unavailable - Apple Intelligence is off in Settings"
        case .unavailable(.modelNotReady):
            return "Unavailable - model still downloading"
        case .unavailable:
            return "Unavailable"
        }
        #else
        return "Framework not present in this build"
        #endif
    }
}
