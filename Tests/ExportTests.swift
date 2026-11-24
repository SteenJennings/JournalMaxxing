import XCTest
import SwiftData
@testable import Dayline

final class ExportTests: XCTestCase {
    private func sampleEntry() -> DayEntry {
        let e = DayEntry(date: Date(timeIntervalSince1970: 1_700_000_000), rawTranscript: "fun at the pool")
        e.polishedText = "A fun day at the pool."
        e.projectTags = ["pool", "family"]
        e.mediaLocalIds = ["ABC-123"]
        return e
    }

    func testJSONExportRoundTrips() throws {
        let data = try JournalExporter.jsonData(entries: [sampleEntry()])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ExportEntry].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.polishedText, "A fun day at the pool.")
        XCTAssertEqual(decoded.first?.projectTags, ["pool", "family"])
        XCTAssertEqual(decoded.first?.mediaLocalIds, ["ABC-123"])
    }

    /// Every field on the entry survives an export — the old test only
    /// checked three, and the format silently dropped id, placeholders,
    /// and both timestamps.
    func testJSONExportRoundTripsAllFields() throws {
        let e = sampleEntry()
        e.id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        e.mood = "happy"
        e.highlightLocalId = "ABC-123"
        e.linkURLs = ["https://example.com"]
        e.placeholders = [Placeholder(note: "call mom", isResolved: false)]
        e.createdAt = Date(timeIntervalSince1970: 1_699_000_000)
        e.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        e.isFavorite = true
        let data = try JournalExporter.jsonData(entries: [e])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ExportEntry].self, from: data)
        guard let d = decoded.first else { return XCTFail("no entry decoded") }
        XCTAssertEqual(d.schemaVersion, ExportEntry.currentSchemaVersion)
        XCTAssertEqual(d.id, e.id)
        XCTAssertEqual(d.mood, "happy")
        XCTAssertEqual(d.highlightLocalId, "ABC-123")
        XCTAssertEqual(d.linkURLs, ["https://example.com"])
        XCTAssertEqual(d.placeholders.map(\.note), ["call mom"])
        XCTAssertEqual(d.createdAt, e.createdAt)
        XCTAssertEqual(d.updatedAt, e.updatedAt)
        XCTAssertTrue(d.isFavorite)
    }

    func testImportRoundTripsAndDedupes() throws {
        let container = try ModelContainer(for: DayEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let data = try JournalExporter.jsonData(entries: [sampleEntry()])
        let first = try JournalImporter.importJSON(data, into: context)
        XCTAssertEqual(first, 1)
        // Re-importing the same file updates instead of duplicating.
        let second = try JournalImporter.importJSON(data, into: context)
        XCTAssertEqual(second, 1)
        let all = try context.fetch(FetchDescriptor<DayEntry>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.polishedText, "A fun day at the pool.")
    }

    func testMarkdownExportContainsEntry() {
        let md = JournalExporter.markdown(entries: [sampleEntry()])
        XCTAssertTrue(md.contains("A fun day at the pool."))
        XCTAssertTrue(md.contains("#pool"))
    }

    func testMarkdownSortsAscendingAndShowsFavoriteLinksAndRawFallback() {
        let early = DayEntry(date: Date(timeIntervalSince1970: 1_600_000_000), rawTranscript: "early raw")
        early.isFavorite = true
        early.linkURLs = ["https://example.com"]
        let late = sampleEntry()
        let md = JournalExporter.markdown(entries: [late, early])
        // Ascending by date, favorite starred, links listed, and an
        // entry with no polished text shows its raw transcript.
        let earlyRange = md.range(of: "early raw")!
        let lateRange = md.range(of: "A fun day at the pool.")!
        XCTAssertLessThan(earlyRange.lowerBound, lateRange.lowerBound)
        XCTAssertTrue(md.contains("★"))
        XCTAssertTrue(md.contains("Links: https://example.com"))
        XCTAssertTrue(md.contains("early raw"))
    }

    func testWriteTempFileRoundTrips() throws {
        let data = Data("hello".utf8)
        guard let url = JournalExporter.writeTempFile(data: data, name: "dayline-test.txt") else {
            return XCTFail("writeTempFile returned nil")
        }
        XCTAssertEqual(url.lastPathComponent, "dayline-test.txt")
        XCTAssertTrue(url.path.contains(FileManager.default.temporaryDirectory.path))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
