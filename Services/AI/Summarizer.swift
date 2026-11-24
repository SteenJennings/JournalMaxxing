import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PolishResult {
    var polished: String
    var tags: [String]
    var mood: String?
}

/// Parses the strict POLISHED:/TAGS:/MOOD: format the on-device model is
/// asked to return. Pure and testable. `polished` is nil when the model
/// returned no POLISHED: line at all — the old code then fell back to the
/// ENTIRE raw response, writing literal `TAGS:` / `MOOD:` lines into the
/// saved entry. A nil polished means "polish failed, use local rules".
enum PolishResponseParser {
    static func parse(_ raw: String) -> (polished: String?, tags: [String], mood: String?) {
        var polishedLines: [String] = []
        var inPolished = false
        var tags: [String] = []
        var mood: String?
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("POLISHED:") {
                inPolished = true
                let first = String(trimmed.dropFirst("POLISHED:".count)).trimmingCharacters(in: .whitespaces)
                if !first.isEmpty { polishedLines.append(first) }
            } else if upper.hasPrefix("TAGS:") {
                inPolished = false
                // Dedupe + cap: the prompt asks for up to 4, but the model
                // has returned "pool, pool, pool, pool, pool" before.
                var seen = Set<String>()
                tags = String(trimmed.dropFirst("TAGS:".count))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty && seen.insert($0).inserted }
                    .prefix(4).map { $0 }
            } else if upper.hasPrefix("MOOD:") {
                inPolished = false
                let m = String(trimmed.dropFirst("MOOD:".count))
                    .trimmingCharacters(in: .whitespaces).lowercased()
                // One word, no punctuation: "happy." or "very happy"
                // used to land in the entry verbatim.
                let word = m.components(separatedBy: .whitespaces).first?
                    .trimmingCharacters(in: .punctuationCharacters) ?? ""
                mood = word.isEmpty || word == "none" ? nil : word
            } else if inPolished {
                // Multi-line polished text: the old parser kept only the
                // first line and silently dropped the rest.
                if !trimmed.isEmpty { polishedLines.append(trimmed) }
            }
        }
        let polished = polishedLines.isEmpty ? nil : polishedLines.joined(separator: "\n")
        return (polished, tags, mood)
    }
}

enum PolishError: Error { case timeout }

@MainActor
class Summarizer: ObservableObject {
    /// Backends are interchangeable on purpose: trying a different model is a
    /// settings change, not a rewrite. `appleFoundation` falls back to
    /// `localRules` automatically when the model is unavailable.
    enum Backend { case appleFoundation, localRules }
    var backend: Backend = .appleFoundation
    @Published private(set) var lastBackendUsed: String = "none"
    private let log = Logger(subsystem: "com.steenjennings.dayline", category: "Summarizer")

    func polishFull(transcript: String) async -> PolishResult {
        if backend == .appleFoundation {
            // Long dictations overflow the model's ~4k-token context, so
            // they go straight to chunked polish instead of failing the
            // single-shot call and dropping the whole entry to fallback.
            if transcript.count > 8000, let chunked = await polishChunked(transcript) {
                lastBackendUsed = "FoundationModels (on-device, chunked)"
                Log.event("Polish", "backend=FoundationModels chunked, tags=\(chunked.tags.joined(separator: ","))")
                return chunked
            }
            if let r = await polishWithFoundationModels(transcript) {
                lastBackendUsed = "FoundationModels (on-device)"
                Log.event("Polish", "backend=FoundationModels, tags=\(r.tags.joined(separator: ","))")
                return r
            }
        }
        lastBackendUsed = "Local rules (fallback)"
        log.info("Polishing with local fallback")
        Log.event("Polish", "backend=localRules FALLBACK (see earlier Polish/FoundationModels lines for why)")
        let polished = transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return PolishResult(polished: polished, tags: extractTags(transcript), mood: nil)
    }

    /// Polish a long transcript in sentence-boundary chunks and stitch.
    /// One chunk failing must not lose the rest: it falls back to its
    /// own raw text plus keyword tags.
    private func polishChunked(_ transcript: String) async -> PolishResult? {
        let chunks = Self.chunkTranscript(transcript)
        guard chunks.count > 1 else { return nil }
        var polishedParts: [String] = []
        var tags: [String] = []
        var mood: String?
        for chunk in chunks {
            if let r = await polishWithFoundationModels(chunk) {
                polishedParts.append(r.polished)
                for t in r.tags where !tags.contains(t) { tags.append(t) }
                if mood == nil { mood = r.mood }
            } else {
                polishedParts.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                for t in extractTags(chunk) where !tags.contains(t) { tags.append(t) }
            }
        }
        return PolishResult(polished: polishedParts.joined(separator: " "),
                            tags: Array(tags.prefix(4)), mood: mood)
    }

    /// Split a long transcript into ~6000-char chunks at sentence
    /// boundaries (word boundaries inside one over-long sentence), so no
    /// chunk exceeds the model's context budget. Pure, so tests can pin it.
    static func chunkTranscript(_ text: String, maxChars: Int = 6000) -> [String] {
        let sentences = text.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var chunks: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { chunks.append(current); current = "" }
        }
        for s in sentences {
            let sentence = s.hasSuffix(".") ? s : s + "."
            if current.isEmpty { current = sentence }
            else if current.count + 1 + sentence.count <= maxChars { current += " " + sentence }
            else {
                flush()
                if sentence.count > maxChars {
                    // One over-long sentence: split at word boundaries.
                    var part = ""
                    for word in sentence.split(separator: " ") {
                        if part.isEmpty { part = String(word) }
                        else if part.count + 1 + word.count <= maxChars { part += " " + word }
                        else { chunks.append(part); part = String(word) }
                    }
                    current = part
                } else {
                    current = sentence
                }
            }
        }
        flush()
        return chunks.isEmpty ? [text] : chunks
    }

    private func polishWithFoundationModels(_ transcript: String) async -> PolishResult? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.availability == .available else {
            log.info("FoundationModels unavailable: \(String(describing: SystemLanguageModel.default.availability), privacy: .public)")
            Log.event("Polish", "FoundationModels unavailable: \(String(describing: SystemLanguageModel.default.availability))")
            return nil
        }
        do {
            let session = LanguageModelSession(instructions: """
                You polish short personal journal transcripts. Preserve the writer's voice and facts. \
                Never invent details that are not in the transcript.
                """)
            let prompt = """
                Polish this journal transcript into 1-2 tight sentences. Extract up to 4 lowercase \
                single-word tags (themes like work, dinner, pool, family, trip, health, building, friends). \
                Name the mood in one lowercase word if it is clear, otherwise leave it empty.
                Respond in exactly this format, nothing else:
                POLISHED: <text>
                TAGS: <comma separated>
                MOOD: <word or empty>

                Transcript: \(transcript)
                """
            // A Foundation Models call that never returns used to hang
            // Polish + Save forever. 30s, then local rules.
            let content = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await session.respond(to: prompt).content }
                group.addTask {
                    try await Task.sleep(for: .seconds(30))
                    throw PolishError.timeout
                }
                guard let first = try await group.next() else { throw PolishError.timeout }
                group.cancelAll()
                return first
            }
            let parsed = PolishResponseParser.parse(content)
            guard let polished = parsed.polished else {
                Log.event("Polish", "FoundationModels returned no POLISHED: line - falling back")
                return nil
            }
            let tags = parsed.tags.isEmpty ? extractTags(transcript) : parsed.tags
            return PolishResult(polished: polished, tags: tags, mood: parsed.mood)
        } catch {
            log.error("FoundationModels polish failed: \(error.localizedDescription, privacy: .public)")
            Log.event("Polish", "FoundationModels polish FAILED: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Deterministic keyword tagging (NaturalLanguage-era fallback and the
    /// safety net when the model returns no tags).
    func extractTags(_ text: String) -> [String] {
        let lower = text.lowercased()
        var t: [String] = []
        // Substring stems keep biting ("friendship" -> work via "ship",
        // "workout" -> work via "work", "we ate." never matched because
        // the stem was "ate " with a trailing space). Whole words for the
        // short stems; "shipped" is its own check because \bship\b does
        // not match inside "shipped".
        if hasWord(lower, "work") || lower.contains("promo") || hasWord(lower, "ship") || lower.contains("shipped") || lower.contains("meeting") { t.append("work") }
        if lower.contains("hik") || lower.contains("trip") || lower.contains("beach") || lower.contains("travel") { t.append("trip") }
        if lower.contains("family") || hasWord(lower, "mom") || hasWord(lower, "dad") { t.append("family") }
        if lower.contains("code") || hasWord(lower, "app") || lower.contains("build") { t.append("building") }
        if lower.contains("dinner") || lower.contains("lunch") || lower.contains("breakfast") || hasWord(lower, "ate") { t.append("dinner") }
        if lower.contains("pool") || lower.contains("swim") { t.append("pool") }
        if lower.contains("gym") || hasWord(lower, "run") || lower.contains("workout") || lower.contains("basketball") { t.append("health") }
        if lower.contains("friend") { t.append("friends") }
        return Array(Set(t).prefix(4))
    }

    /// Whole-word check: substring matching made "moment" tag as family
    /// (contains "mom") and "happy" as building (contains "app"). Short
    /// stems still substring-match on purpose ("ship" -> shipped).
    private func hasWord(_ text: String, _ word: String) -> Bool {
        text.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
    }

    /// Tags actually present across entries - drives the Trends tab so new
    /// tags (dinner, pool...) appear without a code change.
    static func allTags(in entries: [DayEntry]) -> [String] {
        Array(Set(entries.flatMap(\.projectTags))).sorted()
    }

    func trendSummary(entries: [DayEntry], tag: String) async -> String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let filtered = entries
            .filter { $0.projectTags.contains(tag) && $0.date >= cutoff }
            .sorted { $0.date > $1.date }
        guard let mostRecent = filtered.first else {
            return "No days tagged \(tag) in the last 30 days."
        }
        return "You logged \(filtered.count) day\(filtered.count == 1 ? "" : "s") about \(tag) in the last 30 days. Most recent: \(mostRecent.polishedText)"
    }
}
