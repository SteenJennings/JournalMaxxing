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

    func testFavoriteOnlyMattersWithoutMatch() {
        let favorited = PhotoFeatures(labels: [], aestheticScore: 0, isFavorite: true)
        let plain = PhotoFeatures(labels: [], aestheticScore: 0)
        XCTAssertGreaterThan(PhotoRanker.score(features: favorited, transcript: "a quiet day").score,
                             PhotoRanker.score(features: plain, transcript: "a quiet day").score)
    }

    func testAestheticOnlyMattersWithoutMatch() {
        let pretty = PhotoFeatures(labels: [], aestheticScore: 1.0)
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

    func testScoreLowerClamp() {
        let f = PhotoFeatures(labels: [], aestheticScore: -1.0, isUtility: true)
        let s = PhotoRanker.score(features: f, transcript: "a quiet day")
        XCTAssertEqual(s.score, 0.0, "utility penalty + worst aesthetics must not go negative")
    }

    func testQualityScoreTable() {
        let favoriteOnly = PhotoFeatures(labels: [], aestheticScore: 0, isFavorite: true)
        XCTAssertEqual(PhotoRanker.qualityScore(features: favoriteOnly), 0.15 + 0.10, accuracy: 0.001)
        let facesOnly = PhotoFeatures(labels: [], aestheticScore: 0, faceCount: 2)
        XCTAssertEqual(PhotoRanker.qualityScore(features: facesOnly), 0.15 + 0.10, accuracy: 0.001)
        let utilityOnly = PhotoFeatures(labels: [], aestheticScore: 0, isUtility: true)
        XCTAssertEqual(PhotoRanker.qualityScore(features: utilityOnly), 0.0, "utility penalty floors at 0")
        let combined = PhotoFeatures(labels: [], aestheticScore: 1.0, faceCount: 1, isFavorite: true)
        XCTAssertEqual(PhotoRanker.qualityScore(features: combined), 0.30 + 0.10 + 0.10, accuracy: 0.001)
    }

    /// One word matching three labels used to score a full 0.50 semantic.
    /// Semantic credit is by distinct word, not label count.
    func testDistinctWordMatching() {
        let f = PhotoFeatures(labels: ["pool", "pool_party", "swimming_pool"], aestheticScore: 0)
        let s = PhotoRanker.score(features: f, transcript: "pool")
        XCTAssertLessThan(s.score, 0.5)
        XCTAssertEqual(PhotoRanker.matchedWords(features: f, transcript: "pool"), ["pool"])
    }

    func testStemmingMatchesHikeToHiking() {
        let f = PhotoFeatures(labels: ["hiking"])
        XCTAssertTrue(PhotoRanker.matchedLabels(features: f, transcript: "went for a hike").contains("hiking"))
        XCTAssertTrue(PhotoRanker.matchedLabels(features: f, transcript: "hiking all day").contains("hiking"))
    }

    func testMatchedLabelsEdgeCases() {
        let f = PhotoFeatures(labels: ["swimming_pool"])
        XCTAssertTrue(PhotoRanker.matchedLabels(features: f, transcript: "").isEmpty)
        // Plural: stemming closes the old gap — "pools" stems to "pool",
        // which is a word in "swimming_pool".
        XCTAssertTrue(PhotoRanker.matchedLabels(features: f, transcript: "at the pools").contains("swimming_pool"))
        // Two-letter words are dropped by the length filter.
        XCTAssertTrue(PhotoRanker.matchedLabels(features: PhotoFeatures(labels: ["go"]), transcript: "let's go").isEmpty)
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
    func testNoPolishedLineReturnsNil() {
        // The old fallback returned the entire raw response — including
        // literal TAGS:/MOOD: lines — as the entry text. Nil means
        // "polish failed, use local rules".
        let parsed = PolishResponseParser.parse("  Just some text.  ")
        XCTAssertNil(parsed.polished)
        XCTAssertTrue(parsed.tags.isEmpty)
        XCTAssertNil(parsed.mood)
    }
    func testEmptyPolishedLineDoesNotLeakFieldLines() {
        let parsed = PolishResponseParser.parse("POLISHED:\nTAGS: pool\nMOOD: happy")
        XCTAssertNil(parsed.polished)
        XCTAssertFalse(parsed.tags.isEmpty)
    }
    func testMultiLinePolishedTextIsKept() {
        let parsed = PolishResponseParser.parse("POLISHED: First line.\nSecond line here.\nTAGS: pool\nMOOD: happy")
        XCTAssertEqual(parsed.polished, "First line.\nSecond line here.")
    }
    func testTagsDedupedAndCapped() {
        let parsed = PolishResponseParser.parse("POLISHED: Day.\nTAGS: pool, pool, POOL, dinner, family, trip, work\nMOOD: happy")
        XCTAssertEqual(parsed.tags, ["pool", "dinner", "family", "trip"])
    }
    func testCaseInsensitivePrefixesAndMoodNone() {
        let parsed = PolishResponseParser.parse("polished: lower case day\ntags: Pool, POOL\nmood: NONE")
        XCTAssertEqual(parsed.polished, "lower case day")
        XCTAssertEqual(parsed.tags, ["pool"])
        XCTAssertNil(parsed.mood)
    }
    func testMoodSanitizedToOneWord() {
        let parsed = PolishResponseParser.parse("POLISHED: Day.\nTAGS: pool\nMOOD: very happy.")
        XCTAssertEqual(parsed.mood, "very")
    }
}
