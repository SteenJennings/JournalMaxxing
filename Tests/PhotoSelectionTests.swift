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
}
