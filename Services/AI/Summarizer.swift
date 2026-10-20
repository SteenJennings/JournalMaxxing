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
/// asked to return. Pure and testable; any deviation falls back to using the
/// raw response as the polished text.
enum PolishResponseParser {
    static func parse(_ raw: String) -> (polished: String, tags: [String], mood: String?) {
        var polished: String?
        var tags: [String] = []
        var mood: String?
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("POLISHED:") {
                polished = String(trimmed.dropFirst("POLISHED:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.uppercased().hasPrefix("TAGS:") {
                tags = String(trimmed.dropFirst("TAGS:".count))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            } else if trimmed.uppercased().hasPrefix("MOOD:") {
                let m = String(trimmed.dropFirst("MOOD:".count)).trimmingCharacters(in: .whitespaces).lowercased()
                mood = m.isEmpty || m == "none" ? nil : m
            }
        }
        return (polished?.isEmpty == false ? polished! : raw.trimmingCharacters(in: .whitespacesAndNewlines),
                tags, mood)
    }
}

@MainActor
class Summarizer: ObservableObject {
    /// Backends are interchangeable on purpose: trying a different model is a
    /// settings change, not a rewrite. `appleFoundation` falls back to
    /// `localRules` automatically when the model is unavailable.
    enum Backend { case appleFoundation, localRules }
    var backend: Backend = .appleFoundation
    @Published private(set) var lastBackendUsed: String = "none"
    private let log = Logger(subsystem: "com.steenjennings.dayline", category: "Summarizer")

    func polish(transcript: String) async -> (polished: String, tags: [String]) {
        let r = await polishFull(transcript: transcript)
        return (r.polished, r.tags)
    }

    func polishFull(transcript: String) async -> PolishResult {
        if backend == .appleFoundation, let r = await polishWithFoundationModels(transcript) {
            lastBackendUsed = "FoundationModels (on-device)"
            Log.event("Polish", "backend=FoundationModels, tags=\(r.tags.joined(separator: ","))")
            return r
        }
        lastBackendUsed = "Local rules (fallback)"
        log.info("Polishing with local fallback")
        Log.event("Polish", "backend=localRules FALLBACK (see earlier Polish/FoundationModels lines for why)")
        let polished = transcript
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
        return PolishResult(polished: polished, tags: extractTags(transcript), mood: nil)
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
            let response = try await session.respond(to: prompt)
            let parsed = PolishResponseParser.parse(response.content)
            let tags = parsed.tags.isEmpty ? extractTags(transcript) : parsed.tags
            return PolishResult(polished: parsed.polished, tags: tags, mood: parsed.mood)
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
        if lower.contains("work") || lower.contains("promo") || lower.contains("ship") || lower.contains("meeting") { t.append("work") }
        if lower.contains("hik") || lower.contains("trip") || lower.contains("beach") || lower.contains("travel") { t.append("trip") }
        if lower.contains("family") || lower.contains("mom") || lower.contains("dad") { t.append("family") }
        if lower.contains("code") || lower.contains("app") || lower.contains("build") { t.append("building") }
        if lower.contains("dinner") || lower.contains("lunch") || lower.contains("breakfast") || lower.contains("ate ") { t.append("dinner") }
        if lower.contains("pool") || lower.contains("swim") { t.append("pool") }
        if lower.contains("gym") || lower.contains("run") || lower.contains("workout") || lower.contains("basketball") { t.append("health") }
        if lower.contains("friend") { t.append("friends") }
        return Array(Set(t))
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
