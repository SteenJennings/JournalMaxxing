
import SwiftData
import Foundation

@Model
final class DayEntry {
    var id: UUID
    var date: Date
    var rawTranscript: String
    var polishedText: String
    var mood: String?
    var projectTags: [String]
    var highlightLocalId: String?
    var mediaLocalIds: [String]
    var linkURLs: [String]
    var placeholders: [Placeholder]
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool = false

    init(date: Date = .now, rawTranscript: String = "") {
        self.id = UUID()
        self.date = date
        self.rawTranscript = rawTranscript
        self.polishedText = ""
        self.projectTags = []
        self.mediaLocalIds = []
        self.linkURLs = []
        self.placeholders = []
        self.createdAt = .now
        self.updatedAt = .now
    }
}

struct Placeholder: Codable, Identifiable {
    var id: UUID = UUID()
    var note: String
    var isResolved: Bool = false
    var remindAt: Date?
}
