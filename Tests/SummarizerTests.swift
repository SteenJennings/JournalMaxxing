import XCTest
@testable import Dayline

@MainActor
final class SummarizerTests: XCTestCase {
    func testTagExtraction() {
        let s = Summarizer()
        let tags = s.extractTags("Today I shipped the app and went hiking with family")
        XCTAssertTrue(tags.contains("work") || tags.contains("building"))
        XCTAssertTrue(tags.contains("trip"))
    }

    func testNewTagVocabulary() {
        let s = Summarizer()
        let tags = s.extractTags("Dinner with friends, then a swim at the pool")
        XCTAssertTrue(tags.contains("dinner"))
        XCTAssertTrue(tags.contains("pool"))
        XCTAssertTrue(tags.contains("friends"))
    }

    func testPolishNotEmpty() async {
        let s = Summarizer()
        s.backend = .localRules // deterministic in tests; FoundationModels availability varies by host
        let res = await s.polish(transcript: "  today was good, coded a lot  ")
        XCTAssertFalse(res.polished.isEmpty)
    }

    func testTrendSummaryRespectsThirtyDayWindow() async {
        let s = Summarizer()
        let old = DayEntry(date: Calendar.current.date(byAdding: .day, value: -45, to: Date())!, rawTranscript: "old")
        old.polishedText = "An old pool day"
        old.projectTags = ["pool"]
        let summary = await s.trendSummary(entries: [old], tag: "pool")
        XCTAssertTrue(summary.contains("No days tagged"))
    }
}
