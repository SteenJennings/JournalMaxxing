import XCTest
import UIKit
@testable import Dayline

/// The old test only asserted that a fresh PhotoService's empty list
/// suggests nothing — it exercised no PhotoKit path, no ranking, and no
/// fallback. These tests drive `rankedSuggest(candidates:)` through the
/// injected analyzer + thumbnail seams instead.
@MainActor
final class PhotoServiceTests: XCTestCase {

    private struct FakeThumbnails: ThumbnailProviding {
        var image: UIImage? = UIImage()
        func thumbnail(for candidate: RankCandidate) async -> UIImage? { image }
    }

    private final class FakeAnalyzer: CandidateAnalyzer {
        var featuresById: [String: PhotoFeatures]
        init(_ featuresById: [String: PhotoFeatures]) { self.featuresById = featuresById }
        func analyze(_ candidate: RankCandidate, image: UIImage?, transcript: String) async -> ScoredPhotoFeatures? {
            guard let image, let f = featuresById[candidate.localIdentifier] else { return nil }
            return PhotoRanker.score(features: f, transcript: transcript)
        }
    }

    private func candidate(_ id: String, video: Bool = false) -> RankCandidate {
        RankCandidate(localIdentifier: id, isFavorite: false, isVideo: video, asset: nil)
    }

    private func serviceWithFake(features: [String: PhotoFeatures]) -> PhotoService {
        let s = PhotoService()
        s.analyzer = FakeAnalyzer(features)
        s.thumbnails = FakeThumbnails()
        return s
    }

    func testRankedSuggestPicksMatchedThenQuality() async {
        let service = serviceWithFake(features: [
            "A": PhotoFeatures(labels: ["pool"], aestheticScore: -0.5),
            "B": PhotoFeatures(labels: ["sunset"], aestheticScore: 1.0),
            "C": PhotoFeatures(labels: [], aestheticScore: 0.0),
        ])
        let picked = await service.rankedSuggest(
            candidates: [candidate("A"), candidate("B"), candidate("C")],
            transcript: "fun at the pool", limit: 2)
        XCTAssertEqual(picked.map(\.localIdentifier), ["A", "B"])
    }

    func testRankedSuggestEmptyWhenAllThumbnailsFail() async {
        let service = PhotoService()
        service.analyzer = FakeAnalyzer(["A": PhotoFeatures(labels: ["pool"])])
        service.thumbnails = FakeThumbnails(image: nil) // every load fails
        let picked = await service.rankedSuggest(
            candidates: [candidate("A")], transcript: "pool", limit: 2)
        XCTAssertTrue(picked.isEmpty, "no scored items means no picks (the caller falls back to prefix)")
    }

    func testRankedSuggestCachesFeaturesAcrossCalls() async {
        // The second call must not re-analyze: swap in an analyzer that
        // returns nil and assert the picks are unchanged (cache hits).
        let service = serviceWithFake(features: [
            "A": PhotoFeatures(labels: ["pool"], aestheticScore: 0.0),
        ])
        let first = await service.rankedSuggest(
            candidates: [candidate("A")], transcript: "pool", limit: 1)
        XCTAssertEqual(first.map(\.localIdentifier), ["A"])
        service.analyzer = FakeAnalyzer([:]) // nothing new to analyze
        let second = await service.rankedSuggest(
            candidates: [candidate("A")], transcript: "pool", limit: 1)
        XCTAssertEqual(second.map(\.localIdentifier), ["A"], "cache hit scores without the analyzer")
    }

    func testSampledCandidatesStridesAndKeepsVideos() {
        var candidates: [RankCandidate] = []
        for i in 0..<30 { candidates.append(candidate("c\(i)", video: i == 25 || i == 29)) }
        let sampled = PhotoService.sampledCandidates(from: candidates)
        XCTAssertLessThanOrEqual(sampled.count, 26, "24 stride picks + videos not already picked")
        XCTAssertTrue(sampled.contains { $0.localIdentifier == "c25" }, "videos are always included")
        XCTAssertTrue(sampled.contains { $0.localIdentifier == "c29" })
        XCTAssertEqual(sampled.first?.localIdentifier, "c0", "stride covers the start of the day")
        XCTAssertEqual(sampled.last?.localIdentifier, "c29", "stride + videos cover the end of the day")
        // A small day is untouched.
        let small = (0..<5).map { candidate("s\($0)") }
        XCTAssertEqual(PhotoService.sampledCandidates(from: small).count, 5)
    }
}

/// VisionService is testable directly: it takes a plain UIImage.
final class VisionServiceTests: XCTestCase {
    func testFeaturesOnBlankImage() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let features = await VisionService().features(for: image, isFavorite: false, isVideo: false)
        XCTAssertEqual(features.faceCount, 0, "no faces on a solid color image")
        if let score = features.aestheticScore {
            XCTAssertTrue((-1.0...1.0).contains(score), "aesthetic score stays in range")
        }
        XCTAssertLessThanOrEqual(features.labels.count, 8)
    }
}

/// DraftStore: the per-day draft file round-trips and clears.
final class DraftStoreTests: XCTestCase {
    func testSaveRestoreClear() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayline-drafts-\(UUID().uuidString).json")
        let store = DraftStore(fileURL: url)
        let day = Calendar.current.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12))!
        XCTAssertNil(store.draft(for: day))
        store.saveDraft(day: day, text: "half a thought")
        XCTAssertEqual(store.draft(for: day), "half a thought")
        // A second instance over the same file sees it.
        let reopened = DraftStore(fileURL: url)
        XCTAssertEqual(reopened.draft(for: day), "half a thought")
        store.clearDraft(for: day)
        XCTAssertNil(store.draft(for: day))
        try? FileManager.default.removeItem(at: url)
    }

    func testDayKeyFormat() {
        let day = Calendar.current.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12))!
        XCTAssertEqual(DraftStore.dayKey(for: day), "2023-11-14")
    }
}
