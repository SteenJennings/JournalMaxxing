import XCTest
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

    func testMarkdownExportContainsEntry() {
        let md = JournalExporter.markdown(entries: [sampleEntry()])
        XCTAssertTrue(md.contains("A fun day at the pool."))
        XCTAssertTrue(md.contains("#pool"))
    }
}
