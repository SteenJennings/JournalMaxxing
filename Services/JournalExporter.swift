import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A Codable snapshot of a DayEntry for export. DayEntry itself is a
/// SwiftData @Model (not Codable), so exports map through this shape.
/// This file is the app's backup format: if the app is ever deleted,
/// a JSON export saved to Files / iCloud Drive is the recovery path.
/// `schemaVersion` is the format version; `id` is the stable identity
/// an import matches on, so a re-import updates instead of duplicating.
/// The old export dropped `id`, `placeholders`, `createdAt`, and
/// `updatedAt` — a restore silently lost them. New fields decode with
/// defaults so old exports still import.
struct ExportEntry: Codable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int = currentSchemaVersion
    var id: UUID = UUID()
    var date: Date
    var rawTranscript: String
    var polishedText: String
    var mood: String?
    var projectTags: [String]
    var highlightLocalId: String?
    var mediaLocalIds: [String]
    var linkURLs: [String]
    var placeholders: [Placeholder] = []
    var createdAt: Date = .distantPast
    var updatedAt: Date = .distantPast
    var isFavorite: Bool

    init(_ e: DayEntry) {
        schemaVersion = Self.currentSchemaVersion
        id = e.id
        date = e.date
        rawTranscript = e.rawTranscript
        polishedText = e.polishedText
        mood = e.mood
        projectTags = e.projectTags
        highlightLocalId = e.highlightLocalId
        mediaLocalIds = e.mediaLocalIds
        linkURLs = e.linkURLs
        placeholders = e.placeholders
        createdAt = e.createdAt
        updatedAt = e.updatedAt
        isFavorite = e.isFavorite
    }

    /// Tolerant decode: exports written before `schemaVersion` / `id` /
    /// `placeholders` / `createdAt` / `updatedAt` existed still import
    /// (synthesized Decodable does not fall back to property defaults
    /// for missing keys, so this has to be explicit).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        rawTranscript = try c.decode(String.self, forKey: .rawTranscript)
        polishedText = try c.decode(String.self, forKey: .polishedText)
        mood = try c.decodeIfPresent(String.self, forKey: .mood)
        projectTags = try c.decodeIfPresent([String].self, forKey: .projectTags) ?? []
        highlightLocalId = try c.decodeIfPresent(String.self, forKey: .highlightLocalId)
        mediaLocalIds = try c.decodeIfPresent([String].self, forKey: .mediaLocalIds) ?? []
        linkURLs = try c.decodeIfPresent([String].self, forKey: .linkURLs) ?? []
        placeholders = try c.decodeIfPresent([Placeholder].self, forKey: .placeholders) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

/// Import a JSON backup produced by `JournalExporter.jsonData`.
/// Matches on `id` first, then on calendar day, so re-importing the
/// same file updates entries instead of duplicating them. Returns the
/// number of entries created or updated.
enum JournalImporter {
    @discardableResult
    static func importJSON(_ data: Data, into context: ModelContext) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let imported = try decoder.decode([ExportEntry].self, from: data)
        var count = 0
        for e in imported {
            let existing = fetchEntry(id: e.id, date: e.date, in: context)
            let entry = existing ?? DayEntry(date: e.date, rawTranscript: e.rawTranscript)
            entry.id = e.id
            entry.date = e.date
            entry.rawTranscript = e.rawTranscript
            entry.polishedText = e.polishedText
            entry.mood = e.mood
            entry.projectTags = e.projectTags
            entry.highlightLocalId = e.highlightLocalId
            entry.mediaLocalIds = e.mediaLocalIds
            entry.linkURLs = e.linkURLs
            entry.placeholders = e.placeholders
            entry.createdAt = e.createdAt == .distantPast ? entry.createdAt : e.createdAt
            entry.updatedAt = e.updatedAt == .distantPast ? Date() : e.updatedAt
            entry.isFavorite = e.isFavorite
            if existing == nil { context.insert(entry) }
            count += 1
        }
        try context.save()
        Log.event("Import", "imported \(count) entries from JSON backup")
        return count
    }

    private static func fetchEntry(id: UUID, date: Date, in context: ModelContext) -> DayEntry? {
        let byId = FetchDescriptor<DayEntry>(predicate: #Predicate { $0.id == id })
        if let hit = (try? context.fetch(byId))?.first { return hit }
        let start = Calendar.current.startOfDay(for: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
        let byDay = FetchDescriptor<DayEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(byDay))?.first
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
            out += "\n## \(df.string(from: e.date))\(e.isFavorite ? " ★" : "")\n\n"
            out += (e.polishedText.isEmpty ? e.rawTranscript : e.polishedText) + "\n"
            if !e.projectTags.isEmpty {
                out += "\nTags: " + e.projectTags.map { "#\($0)" }.joined(separator: " ") + "\n"
            }
            if let mood = e.mood { out += "Mood: \(mood)\n" }
            if !e.mediaLocalIds.isEmpty {
                out += "Photos: " + e.mediaLocalIds.joined(separator: ", ") + "\n"
            }
            if !e.linkURLs.isEmpty {
                out += "Links: " + e.linkURLs.joined(separator: ", ") + "\n"
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
