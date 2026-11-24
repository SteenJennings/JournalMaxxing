import XCTest
@testable import Dayline

@MainActor
final class SummarizerTests: XCTestCase {
    func testTagExtraction() {
        let s = Summarizer()
        let tags = s.extractTags("Today I shipped the app and went hiking with family")
        XCTAssertTrue(tags.contains("work"))
        XCTAssertTrue(tags.contains("building"))
        XCTAssertTrue(tags.contains("trip"))
        XCTAssertTrue(tags.contains("family"))
    }

    func testNewTagVocabulary() {
        let s = Summarizer()
        let tags = s.extractTags("Dinner with friends, then a swim at the pool")
        XCTAssertTrue(tags.contains("dinner"))
        XCTAssertTrue(tags.contains("pool"))
        XCTAssertTrue(tags.contains("friends"))
    }

    /// Word-boundary regressions: substring matching once made "moment"
    /// tag as family (contains "mom"), "happy" as building (contains
    /// "app"), and "friendship" as work (contains "ship"). Locked in.
    func testWordBoundaryTagRegressions() {
        let s = Summarizer()
        XCTAssertFalse(s.extractTags("a quiet moment with my thoughts").contains("family"))
        XCTAssertFalse(s.extractTags("happy to be home").contains("building"))
        XCTAssertFalse(s.extractTags("our friendship is the best").contains("work"))
        XCTAssertFalse(s.extractTags("we went for a workout").contains("work"))
        // Positive controls: the real words still tag.
        XCTAssertTrue(s.extractTags("mom called").contains("family"))
        XCTAssertTrue(s.extractTags("building the app").contains("building"))
        XCTAssertTrue(s.extractTags("we went for a workout").contains("health"))
        // "ate" at the end of a sentence (no trailing space) tags dinner.
        XCTAssertTrue(s.extractTags("we ate").contains("dinner"))
    }

    func testPolishNotEmpty() async {
        let s = Summarizer()
        s.backend = .localRules // deterministic in tests; FoundationModels availability varies by host
        let res = await s.polishFull(transcript: "  today was good,   coded a lot  ")
        XCTAssertFalse(res.polished.isEmpty)
        XCTAssertEqual(res.polished, "today was good, coded a lot", "fallback trims and collapses whitespace")
        XCTAssertEqual(s.lastBackendUsed, "Local rules (fallback)")
    }

    func testTrendSummaryRespectsThirtyDayWindow() async {
        let s = Summarizer()
        let old = DayEntry(date: Calendar.current.date(byAdding: .day, value: -45, to: Date())!, rawTranscript: "old")
        old.polishedText = "An old pool day"
        old.projectTags = ["pool"]
        let summary = await s.trendSummary(entries: [old], tag: "pool")
        XCTAssertTrue(summary.contains("No days tagged"))
    }

    func testTrendSummaryPositiveSingularAndPlural() async {
        let s = Summarizer()
        let recent = DayEntry(date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!, rawTranscript: "pool")
        recent.polishedText = "A pool day"
        recent.projectTags = ["pool"]
        let one = await s.trendSummary(entries: [recent], tag: "pool")
        XCTAssertTrue(one.contains("You logged 1 day about pool"))
        XCTAssertTrue(one.contains("Most recent: A pool day"))

        let older = DayEntry(date: Calendar.current.date(byAdding: .day, value: -10, to: Date())!, rawTranscript: "pool again")
        older.polishedText = "Another pool day"
        older.projectTags = ["pool"]
        let two = await s.trendSummary(entries: [recent, older], tag: "pool")
        XCTAssertTrue(two.contains("You logged 2 days about pool"))

        // Boundary: 29 days in, 31 days out.
        let inWindow = DayEntry(date: Calendar.current.date(byAdding: .day, value: -29, to: Date())!, rawTranscript: "pool")
        inWindow.polishedText = "Edge pool day"
        inWindow.projectTags = ["pool"]
        let boundary = await s.trendSummary(entries: [inWindow], tag: "pool")
        XCTAssertTrue(boundary.contains("1 day about pool"))
        let outWindow = DayEntry(date: Calendar.current.date(byAdding: .day, value: -31, to: Date())!, rawTranscript: "pool")
        outWindow.polishedText = "Too old"
        outWindow.projectTags = ["pool"]
        let outside = await s.trendSummary(entries: [outWindow], tag: "pool")
        XCTAssertTrue(outside.contains("No days tagged"))
    }

    func testAllTagsDedupesAndSorts() {
        let a = DayEntry(rawTranscript: "a")
        a.projectTags = ["pool", "dinner"]
        let b = DayEntry(rawTranscript: "b")
        b.projectTags = ["pool", "family"]
        XCTAssertEqual(Summarizer.allTags(in: [a, b]), ["dinner", "family", "pool"])
    }

    func testChunkTranscriptSplitsLongText() {
        let sentence = "We walked down to the water and the light was unreal over the bay"
        let text = Array(repeating: sentence, count: 200).joined(separator: ". ") + "."
        XCTAssertGreaterThan(text.count, 8000)
        let chunks = Summarizer.chunkTranscript(text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 6000 }, "no chunk may exceed the budget")
        // Rejoined chunks cover the whole transcript.
        let rejoined = chunks.joined(separator: " ")
        XCTAssertTrue(rejoined.contains("We walked down"))
        XCTAssertTrue(rejoined.contains("unreal over the bay"))
    }
}
