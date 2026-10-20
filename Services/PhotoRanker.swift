import Foundation

/// Observable features extracted from one photo/video, kept as a plain value
/// type so the ranking logic is pure and unit-testable without PhotoKit.
struct PhotoFeatures: Equatable {
    var labels: [String] = []            // Vision classification labels, e.g. ["swimming_pool", "people"]
    var aestheticScore: Double? = nil    // Vision aesthetics, -1...1 (higher = prettier)
    var isUtility: Bool = false          // Vision says screenshot / receipt / document-like
    var faceCount: Int = 0
    var isFavorite: Bool = false
    var isVideo: Bool = false
}

struct ScoredPhotoFeatures: Equatable {
    var features: PhotoFeatures
    var score: Double                    // 0...1
    var matchedLabels: [String]
}

/// Ranking = semantic match to what you said (50%) + how good the photo is
/// aesthetically (30%) + people in it (10%) + you favorited it (10%).
/// Utility images (screenshots, receipts) are penalised. This is a proxy for
/// "best / most fun", not a judgement - weights live here so they are tunable
/// in one place once real results on a real library can be compared.
enum PhotoRanker {
    static func score(features: PhotoFeatures, transcript: String) -> ScoredPhotoFeatures {
        let matched = matchedLabels(features: features, transcript: transcript)
        let semantic = min(Double(matched.count), 3.0) / 3.0 * 0.50
        let aesthetic = ((features.aestheticScore ?? 0) + 1.0) / 2.0 * 0.30
        let people = features.faceCount > 0 ? 0.10 : 0.0
        let favorite = features.isFavorite ? 0.10 : 0.0
        var total = semantic + aesthetic + people + favorite
        if features.isUtility { total -= 0.30 }
        return ScoredPhotoFeatures(features: features,
                                   score: min(max(total, 0), 1),
                                   matchedLabels: matched)
    }

    static func matchedLabels(features: PhotoFeatures, transcript: String) -> [String] {
        let words = Set(
            transcript.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
        guard !words.isEmpty else { return [] }
        return features.labels.filter { label in
            let labelWords = label.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .components(separatedBy: " ")
            return labelWords.contains { words.contains($0) }
        }
    }
}

/// Pulls http(s) links out of free text (transcripts mention links; entries
/// store them so Scrapbook can render real LPLinkViews).
enum LinkExtractor {
    static func extract(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var urls: [String] = []
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let url = match?.url?.absoluteString, !urls.contains(url) { urls.append(url) }
        }
        return urls
    }
}
