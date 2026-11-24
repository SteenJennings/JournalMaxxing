import XCTest
@testable import Dayline

/// Two-pool selection (Steen's editorial rule): slots go first to photos
/// matching the text, then to the day's best photos on quality alone.
final class PhotoSelectionTests: XCTestCase {

    private func item(_ id: String, labels: [String], matched: [String],
                      aesthetic: Double, favorite: Bool = false,
                      faces: Int = 0, utility: Bool = false)
        -> (item: String, features: PhotoFeatures, scored: ScoredPhotoFeatures) {
        let features = PhotoFeatures(labels: labels, aestheticScore: aesthetic,
                                     isUtility: utility, faceCount: faces,
                                     isFavorite: favorite, isVideo: false)
        let scored = ScoredPhotoFeatures(features: features,
                                         score: Double(matched.count) / 3.0 * 0.5 + ((aesthetic + 1) / 2) * 0.3,
                                         matchedLabels: matched)
        return (id, features, scored)
    }

    func testMatchedGetMajorityThenBestOfDayFills() {
        let items = [
            item("A", labels: ["pool"], matched: ["pool", "water"], aesthetic: -0.6),  // strong match, ugly
            item("B", labels: ["taco"], matched: ["taco"], aesthetic: 0.2),           // weak match
            item("C", labels: ["sunset"], matched: [], aesthetic: 1.0),               // gorgeous, unmentioned
            item("D", labels: [" receipt "], matched: [], aesthetic: 0.4),
            item("E", labels: ["dog"], matched: [], aesthetic: 0.0),
        ]
        let picked = PhotoRanker.select(items: items, limit: 3)
        XCTAssertEqual(picked, ["A", "B", "C"],
                       "2 matched slots (60% of 3, ceil) then the best quality photo fills the last slot")
    }

    func testNoMatchesMeansPureBestOfDay() {
        let items = [
            item("A", labels: [], matched: [], aesthetic: -0.5),
            item("B", labels: [], matched: [], aesthetic: 0.9, favorite: true),
            item("C", labels: [], matched: [], aesthetic: 0.3, faces: 2),
        ]
        let picked = PhotoRanker.select(items: items, limit: 2)
        XCTAssertEqual(picked, ["B", "C"])
    }

    func testUtilityPhotosLoseTheQualityPool() {
        let items = [
            item("SHOT", labels: [], matched: [], aesthetic: 1.0, utility: true),
            item("REAL", labels: [], matched: [], aesthetic: 0.2),
        ]
        let picked = PhotoRanker.select(items: items, limit: 1)
        XCTAssertEqual(picked, ["REAL"], "a screenshot's quality is penalised below a real photo")
    }

    func testFewerMatchedThanSlotsFillsFromQuality() {
        let items = [
            item("M", labels: ["hike"], matched: ["hike"], aesthetic: -0.9),
            item("Q1", labels: [], matched: [], aesthetic: 0.8),
            item("Q2", labels: [], matched: [], aesthetic: 0.5),
            item("Q3", labels: [], matched: [], aesthetic: -0.2),
        ]
        let picked = PhotoRanker.select(items: items, limit: 3)
        XCTAssertEqual(picked, ["M", "Q1", "Q2"])
    }

    func testSelectBoundaryInputs() {
        let items = [
            item("M", labels: ["hike"], matched: ["hike"], aesthetic: 0.0),
            item("Q", labels: [], matched: [], aesthetic: 0.5),
        ]
        XCTAssertTrue(PhotoRanker.select(items: [], limit: 3).isEmpty)
        XCTAssertTrue(PhotoRanker.select(items: items, limit: 0).isEmpty)
        // Limit larger than the pool returns everything, matched first.
        XCTAssertEqual(PhotoRanker.select(items: items, limit: 10), ["M", "Q"])
    }

    /// At small limits the text pool must not take every slot: limit 2
    /// with 2 matched items keeps one quality slot.
    func testSmallLimitKeepsAQualitySlot() {
        let items = [
            item("A", labels: ["pool"], matched: ["pool"], aesthetic: -0.9),
            item("B", labels: ["taco"], matched: ["taco"], aesthetic: -0.9),
            item("C", labels: ["sunset"], matched: [], aesthetic: 1.0),
        ]
        let picked = PhotoRanker.select(items: items, limit: 2)
        XCTAssertEqual(picked.count, 2)
        XCTAssertTrue(picked.contains("C"), "one slot must go to the best-of-day photo")
        XCTAssertEqual(picked.filter { $0 == "A" || $0 == "B" }.count, 1)
    }

    func testEqualQualityKeepsInputOrder() {
        // For unmatched items, quality and score are the same function
        // of the same inputs, so the score tie-break can never fire —
        // equal-quality items keep their input order (Swift's sort is
        // stable). Locked in so a future "fix" doesn't reorder the pool.
        let tied = [
            item("FIRST", labels: [], matched: [], aesthetic: 0.5),
            item("SECOND", labels: [], matched: [], aesthetic: 0.5),
        ]
        let picked = PhotoRanker.select(items: tied, limit: 2)
        XCTAssertEqual(picked, ["FIRST", "SECOND"])
    }
}
