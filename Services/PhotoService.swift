import Photos
import Foundation
import UIKit

/// One candidate for ranking. Carries the PHAsset for production use,
/// but tests can build candidates with `asset: nil` and inject a fake
/// analyzer — the old code was untestable because it reached straight
/// into PhotoKit and a private concrete VisionService.
struct RankCandidate {
    var localIdentifier: String
    var isFavorite: Bool
    var isVideo: Bool
    var asset: PHAsset?
}

/// The Vision step, behind a protocol so tests can inject canned
/// features. Production implementation is `VisionCandidateAnalyzer`.
protocol CandidateAnalyzer {
    func analyze(_ candidate: RankCandidate, image: UIImage?, transcript: String) async -> ScoredPhotoFeatures?
}

struct VisionCandidateAnalyzer: CandidateAnalyzer {
    private let vision = VisionService()
    func analyze(_ candidate: RankCandidate, image: UIImage?, transcript: String) async -> ScoredPhotoFeatures? {
        guard let image else { return nil }
        let features = await vision.features(for: image,
                                             isFavorite: candidate.isFavorite,
                                             isVideo: candidate.isVideo)
        return PhotoRanker.score(features: features, transcript: transcript)
    }
}

/// The thumbnail step, behind a protocol for the same reason.
protocol ThumbnailProviding {
    func thumbnail(for candidate: RankCandidate) async -> UIImage?
}

struct PhotoKitThumbnails: ThumbnailProviding {
    func thumbnail(for candidate: RankCandidate) async -> UIImage? {
        guard let asset = candidate.asset else { return nil }
        return await AssetMediaLoader.image(for: asset, targetSize: CGSize(width: 260, height: 260))
    }
}

// NSObject: PHPhotoLibraryChangeObserver inherits from NSObjectProtocol,
// which a Swift class cannot conform to without inheriting NSObject.
@MainActor
class PhotoService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var todaysAssets: [PHAsset] = []
    @Published var permissionStatus: PHAuthorizationStatus = .notDetermined
    /// The day `todaysAssets` currently covers (usually TodayView's
    /// selectedDate); the library observer re-fetches this day.
    private var currentDay: Date = Date()
    private var changeGeneration = 0
    /// In-memory feature cache: Vision runs once per asset per launch,
    /// not once per polish (the old code re-analyzed every photo on every
    /// Polish + Save). Keyed by localIdentifier.
    private var featureCache: [String: PhotoFeatures] = [:]
    var analyzer: any CandidateAnalyzer = VisionCandidateAnalyzer()
    var thumbnails: any ThumbnailProviding = PhotoKitThumbnails()

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    /// The library changed while the app was open (photos added, an album
    /// edited, limited-access picks changed): re-fetch the working day so
    /// the pool never goes stale. Debounced — the callback fires in bursts.
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.changeGeneration += 1
            let generation = self.changeGeneration
            try? await Task.sleep(for: .milliseconds(500))
            guard generation == self.changeGeneration else { return }
            Log.event("Photos", "library changed - re-fetching \(self.currentDay.formatted(date: .abbreviated, time: .omitted))")
            self.fetchAssets(on: self.currentDay)
        }
    }

    func requestPermissionAndFetch() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                self?.permissionStatus = status
                Log.event("Photos", "library authorization: \(status.rawValue) (3=authorized, 4=limited)")
                if status == .authorized || status == .limited {
                    self?.fetchTodaysPhotos()
                }
            }
        }
    }

    func fetchTodaysPhotos() { fetchAssets(on: Date()) }

    /// All media (photos, videos, Live Photos) created on the given day.
    /// Date is the primary filter for suggestions: the transcript is about a
    /// day, so the candidate pool is that day's library.
    func fetchAssets(on date: Date) {
        currentDay = date
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)
        var arr: [PHAsset] = []
        result.enumerateObjects { a, _, _ in arr.append(a) }
        todaysAssets = arr
        Log.event("Photos", "fetched \(arr.count) assets for \(start.formatted(date: .abbreviated, time: .omitted))")
    }

    /// Day fetch usable without an instance (the day browser and the entry
    /// editor ask for arbitrary dates; Today uses the instance path).
    static func assets(on date: Date) async -> [PHAsset] {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            Log.event("Photos", "browser fetch denied (authorization \(status.rawValue))")
            return []
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@",
                                        start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var arr: [PHAsset] = []
        result.enumerateObjects { a, _, _ in arr.append(a) }
        Log.event("Photos", "browser fetched \(arr.count) assets for \(start.formatted(date: .abbreviated, time: .omitted))")
        return arr
    }

    /// Fast fallback: no analysis, first few assets. Used while ranked
    /// suggestions are still computing.
    func suggest(for transcript: String) -> [PHAsset] {
        Array(todaysAssets.prefix(5))
    }

    /// The ranking candidate pool: at most `cap` candidates, stride-
    /// sampled across the day so a 300-photo day isn't represented by
    /// its last 24 (the old code took `prefix(24)` of a newest-first
    /// list). Videos are always included — they carry the day's motion.
    static func sampledCandidates(from candidates: [RankCandidate], cap: Int = 24) -> [RankCandidate] {
        guard candidates.count > cap else { return candidates }
        let videos = candidates.filter(\.isVideo)
        let step = Double(candidates.count) / Double(cap)
        var picked: [RankCandidate] = []
        var seen: Set<String> = []
        for i in 0..<cap {
            let c = candidates[min(Int(Double(i) * step), candidates.count - 1)]
            if seen.insert(c.localIdentifier).inserted { picked.append(c) }
        }
        for v in videos where seen.insert(v.localIdentifier).inserted { picked.append(v) }
        return picked
    }

    /// Ranked suggestions: thumbnail each candidate (capped, for battery),
    /// extract Vision features, score against the transcript with PhotoRanker.
    /// Analyzes in parallel (4 at a time) with an in-memory feature cache,
    /// and respects task cancellation.
    func rankedSuggest(for transcript: String, limit: Int = 5) async -> [PHAsset] {
        let all = todaysAssets.map {
            RankCandidate(localIdentifier: $0.localIdentifier,
                          isFavorite: $0.isFavorite,
                          isVideo: $0.mediaType == .video,
                          asset: $0)
        }
        let candidates = Self.sampledCandidates(from: all)
        Log.event("Photos", "rankedSuggest: \(candidates.count) candidates from \(todaysAssets.count) assets")
        guard !candidates.isEmpty else { Log.event("Photos", "rankedSuggest: NO candidates (empty day or no permission)"); return [] }
        let picked = await rankedSuggest(candidates: candidates, transcript: transcript, limit: limit)
        if picked.isEmpty { Log.event("Photos", "rankedSuggest: 0 scored, using prefix fallback"); return suggest(for: transcript) }
        Log.event("Photos", "rankedSuggest: two-pool picked \(picked.count) of \(candidates.count) candidates")
        return picked.compactMap(\.asset)
    }

    /// The testable core: scores candidates and returns the picked ones.
    /// Cache hits are scored synchronously; the rest analyze in parallel.
    func rankedSuggest(candidates: [RankCandidate], transcript: String, limit: Int = 5) async -> [RankCandidate] {
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let analyzer = self.analyzer
        let thumbnails = self.thumbnails
        let cached = featureCache
        var items: [(candidate: RankCandidate, scored: ScoredPhotoFeatures)] = []
        var toAnalyze: [RankCandidate] = []
        for c in candidates {
            if let f = cached[c.localIdentifier] {
                items.append((c, PhotoRanker.score(features: f, transcript: transcript)))
            } else {
                toAnalyze.append(c)
            }
        }
        // Parallel in chunks of 4: Vision + thumbnail fetches are the
        // slow part, and unbounded concurrency spikes memory on big days.
        for chunk in toAnalyze.chunked(into: 4) {
            guard !Task.isCancelled else { break }
            let analyzed: [(RankCandidate, ScoredPhotoFeatures)] = await withTaskGroup(of: (RankCandidate, ScoredPhotoFeatures)?.self) { group in
                for c in chunk {
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        let image = await thumbnails.thumbnail(for: c)
                        guard let scored = await analyzer.analyze(c, image: image, transcript: transcript) else { return nil }
                        return (c, scored)
                    }
                }
                var out: [(RankCandidate, ScoredPhotoFeatures)] = []
                for await r in group { if let r { out.append(r) } }
                return out
            }
            for (c, scored) in analyzed {
                featureCache[c.localIdentifier] = scored.features
                items.append((c, scored))
            }
        }
        guard !items.isEmpty else { return [] }
        return PhotoRanker.select(items: items.map { (item: $0.candidate, features: $0.scored.features, scored: $0.scored) }, limit: limit)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
