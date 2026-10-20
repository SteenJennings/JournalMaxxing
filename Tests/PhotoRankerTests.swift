import XCTest
@testable import Dayline

final class PhotoRankerTests: XCTestCase {
    func testSemanticMatchRaisesScore() {
        let pool = PhotoFeatures(labels: ["swimming_pool", "people"], aestheticScore: 0.5, faceCount: 2)
        let receipt = PhotoFeatures(labels: ["document"], aestheticScore: 0.5, isUtility: true)
        let poolScore = PhotoRanker.score(features: pool, transcript: "so fun at the pool today")
        let receiptScore = PhotoRanker.score(features: receipt, transcript: "so fun at the pool today")
        XCTAssertTrue(poolScore.matchedLabels.contains("swimming_pool"))
        XCTAssertGreaterThan(poolScore.score, receiptScore.score)
    }

    func testFavoriteAndAestheticMatterWithoutMatch() {
        let pretty = PhotoFeatures(labels: [], aestheticScore: 1.0, isFavorite: true)
        let dull = PhotoFeatures(labels: [], aestheticScore: -1.0)
        XCTAssertGreaterThan(PhotoRanker.score(features: pretty, transcript: "a quiet day").score,
                             PhotoRanker.score(features: dull, transcript: "a quiet day").score)
    }

    func testScoreClampedToUnitRange() {
        let f = PhotoFeatures(labels: ["pool", "pool_party", "swimming_pool"],
                                aestheticScore: 1, faceCount: 3, isFavorite: true)
        let s = PhotoRanker.score(features: f, transcript: "pool pool swimming")
        XCTAssertLessThanOrEqual(s.score, 1.0)
        XCTAssertGreaterThanOrEqual(s.score, 0.0)
    }
}

final class LinkExtractorTests: XCTestCase {
    func testExtractsAndDedupesLinks() {
        let links = LinkExtractor.extract(from: "pics at https://example.com/trip and again https://example.com/trip plus https://apple.com")
        XCTAssertEqual(links, ["https://example.com/trip", "https://apple.com"])
    }
    func testNoLinks() {
        XCTAssertTrue(LinkExtractor.extract(from: "just a normal day").isEmpty)
    }
}

final class PolishResponseParserTests: XCTestCase {
    func testParsesStructuredResponse() {
        let parsed = PolishResponseParser.parse("POLISHED: Great day at the pool.\nTAGS: pool, family\nMOOD: happy")
        XCTAssertEqual(parsed.polished, "Great day at the pool.")
        XCTAssertEqual(parsed.tags, ["pool", "family"])
        XCTAssertEqual(parsed.mood, "happy")
    }
    func testFallsBackToRawText() {
        let parsed = PolishResponseParser.parse("  Just some text.  ")
        XCTAssertEqual(parsed.polished, "Just some text.")
        XCTAssertTrue(parsed.tags.isEmpty)
        XCTAssertNil(parsed.mood)
    }
}
