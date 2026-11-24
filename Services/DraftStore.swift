import Foundation

/// Persists in-progress drafts — one per day — so a dictation is never
/// held only in memory. The swarm audit (2026-11-23) found two ways to
/// lose unsaved work: iOS killing the app before Polish + Save, and
/// tapping another calendar day, which reset the editor unconditionally.
/// Drafts are keyed by day ("2026-10-21") and stored as a small JSON
/// file in Application Support, next to the diagnostics log. A draft is
/// cleared when its day is saved; a draft for a day with a saved entry is
/// the newer work, so it wins on load.
final class DraftStore {
    static let shared = DraftStore()

    struct Draft: Codable {
        var text: String
        var savedAt: Date
    }

    private let fileURL: URL?
    private let lock = NSLock()

    init(fileURL: URL? = DraftStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dayline-drafts.json")
    }

    /// "2026-10-21" — the day key, in the device's calendar.
    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func saveDraft(day: Date, text: String) {
        guard !text.isEmpty, let fileURL else { return }
        lock.lock()
        var all = readLocked()
        all[Self.dayKey(for: day)] = Draft(text: text, savedAt: Date())
        writeLocked(all, to: fileURL)
        lock.unlock()
    }

    func draft(for day: Date) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return readLocked()[Self.dayKey(for: day)]?.text
    }

    func clearDraft(for day: Date) {
        guard let fileURL else { return }
        lock.lock()
        var all = readLocked()
        all.removeValue(forKey: Self.dayKey(for: day))
        writeLocked(all, to: fileURL)
        lock.unlock()
    }

    private func readLocked() -> [String: Draft] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Draft].self, from: data) else { return [:] }
        return decoded
    }

    private func writeLocked(_ all: [String: Draft], to url: URL) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
