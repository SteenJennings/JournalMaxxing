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
        // Semantic credit is by DISTINCT transcript word matched, not by
        // label count: one word ("pool") matching three labels ("pool",
        // "swimming_pool", "water") used to score a full 0.50.
        let distinctWords = matchedWords(features: features, transcript: transcript)
        let semantic = min(Double(distinctWords.count), 3.0) / 3.0 * 0.50
        let aesthetic = ((features.aestheticScore ?? 0) + 1.0) / 2.0 * 0.30
        let people = features.faceCount > 0 ? 0.10 : 0.0
        let favorite = features.isFavorite ? 0.10 : 0.0
        var total = semantic + aesthetic + people + favorite
        if features.isUtility { total -= 0.30 }
        return ScoredPhotoFeatures(features: features,
                                   score: min(max(total, 0), 1),
                                   matchedLabels: matched)
    }

    /// Quality alone, ignoring the text: aesthetics + people + favorite,
    /// minus the utility penalty. This drives the best-of-day pool - the
    /// sunset shot the entry never mentioned but the page still deserves.
    static func qualityScore(features: PhotoFeatures) -> Double {
        let aesthetic = ((features.aestheticScore ?? 0) + 1.0) / 2.0 * 0.30
        let people = features.faceCount > 0 ? 0.10 : 0.0
        let favorite = features.isFavorite ? 0.10 : 0.0
        var quality = aesthetic + people + favorite
        if features.isUtility { quality -= 0.30 }
        return min(max(quality, 0), 1)
    }

    /// Two-pool selection (Steen's editorial rule, 2026-10-20): most slots
    /// go to photos that match what the text says; the remaining slots go
    /// to the day's best photos on quality alone, mentioned or not. If
    /// nothing matches the text, the whole set is best-of-day. Returned in
    /// pick order: matched by relevance, then quality picks by quality.
    static func select<T>(items: [(item: T, features: PhotoFeatures, scored: ScoredPhotoFeatures)],
                          limit: Int,
                          matchedFraction: Double = 0.6) -> [T] {
        guard limit > 0, !items.isEmpty else { return [] }
        let indexed = Array(items.enumerated())
        let matchedOffsets = indexed
            .filter { !$0.element.scored.matchedLabels.isEmpty }
            .sorted { a, b in
                if a.element.scored.matchedLabels.count != b.element.scored.matchedLabels.count {
                    return a.element.scored.matchedLabels.count > b.element.scored.matchedLabels.count
                }
                return a.element.scored.score > b.element.scored.score
            }
            .map(\.offset)
        var matchedSlots = min(matchedOffsets.count,
                               max(1, Int(ceil(Double(limit) * matchedFraction))))
        // At small limits the text pool could take every slot (2 matched,
        // limit 2) and the two-pool rule quietly became one-pool. Keep at
        // least one quality slot when unmatched items exist.
        if limit >= 2, matchedSlots >= limit, matchedOffsets.count < items.count {
            matchedSlots = limit - 1
        }
        var chosen = Array(matchedOffsets.prefix(matchedSlots))
        if chosen.count < limit {
            let chosenSet = Set(chosen)
            let rest = indexed
                .filter { !chosenSet.contains($0.offset) }
                .sorted { a, b in
                    let qa = qualityScore(features: a.element.features)
                    let qb = qualityScore(features: b.element.features)
                    if qa != qb { return qa > qb }
                    return a.element.scored.score > b.element.scored.score
                }
                .map(\.offset)
            chosen.append(contentsOf: rest.prefix(limit - chosen.count))
        }
        return chosen.map { items[$0].item }
    }

    /// The distinct transcript words that at least one label matched.
    /// Used for scoring (see `score`); a word counts once no matter how
    /// many labels it matches.
    static func matchedWords(features: PhotoFeatures, transcript: String) -> Set<String> {
        let words = transcriptWords(transcript)
        guard !words.isEmpty else { return [] }
        var matched: Set<String> = []
        for label in features.labels {
            let labelWords = label.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .components(separatedBy: " ")
            for lw in labelWords where words.contains(stem(lw)) {
                matched.insert(stem(lw))
            }
        }
        return matched
    }

    static func matchedLabels(features: PhotoFeatures, transcript: String) -> [String] {
        let words = transcriptWords(transcript)
        guard !words.isEmpty else { return [] }
        return features.labels.filter { label in
            let labelWords = label.lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .components(separatedBy: " ")
            return labelWords.contains { words.contains(stem($0)) }
        }
    }

    private static func transcriptWords(_ transcript: String) -> Set<String> {
        Set(
            transcript.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
                .map { stem($0) }
        )
    }

    /// Light stemming so "hike" matches a "hiking" label and "dogs"
    /// matches "dog". Deliberately crude — Vision labels are short and
    /// the cost of a false positive here is one photo slot.
    static func stem(_ word: String) -> String {
        var w = word
        if w.count > 5, w.hasSuffix("ing") { w = String(w.dropLast(3)) }
        else if w.count > 4, w.hasSuffix("ed") { w = String(w.dropLast(2)) }
        else if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { w = String(w.dropLast()) }
        // A trailing "e" goes too, so "hike" and "hiking" share a root
        // ("hik") instead of never matching each other.
        if w.count > 3, w.hasSuffix("e") { w = String(w.dropLast()) }
        // Collapse a doubled trailing consonant left by the strip
        // ("swimming" -> "swimm" -> "swim", "stopped" -> "stop").
        if w.count > 2, let last = w.last, w.dropLast().last == last, !"aeiou".contains(last) {
            w = String(w.dropLast())
        }
        return w
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
