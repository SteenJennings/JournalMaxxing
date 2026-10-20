import Photos
import Foundation

@MainActor
class PhotoService: ObservableObject {
    @Published var todaysAssets: [PHAsset] = []
    @Published var permissionStatus: PHAuthorizationStatus = .notDetermined
    private let vision = VisionService()

    func requestPermissionAndFetch() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            Task { @MainActor in
                self?.permissionStatus = status
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
    }

    /// Fast fallback: no analysis, first few assets. Used while ranked
    /// suggestions are still computing.
    func suggest(for transcript: String) -> [PHAsset] {
        Array(todaysAssets.prefix(5))
    }

    /// Ranked suggestions: thumbnail each candidate (capped, for battery),
    /// extract Vision features, score against the transcript with PhotoRanker.
    /// Analysis results are computed fresh per call in v1; caching extracted
    /// features per localIdentifier is the known next optimisation.
    func rankedSuggest(for transcript: String, limit: Int = 5) async -> [PHAsset] {
        let candidates = Array(todaysAssets.prefix(24))
        guard !candidates.isEmpty else { return [] }
        var scored: [(asset: PHAsset, score: Double)] = []
        for asset in candidates {
            guard let thumb = await AssetMediaLoader.image(
                for: asset, targetSize: CGSize(width: 260, height: 260)) else { continue }
            let features = await vision.features(for: thumb,
                                                 isFavorite: asset.isFavorite,
                                                 isVideo: asset.mediaType == .video)
            let result = PhotoRanker.score(features: features, transcript: transcript)
            scored.append((asset, result.score))
        }
        if scored.isEmpty { return suggest(for: transcript) }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map(\.asset)
    }
}
