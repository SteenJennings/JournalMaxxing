import SwiftData
import Foundation

/// One-off housekeeping over the stored journal. The one-entry-per-day
/// invariant is enforced by fetch-then-update in the save path, but a
/// timezone change or a DST edge can make the day-window fetch miss the
/// existing row and insert a second one; the older row then hides from
/// Today while still appearing in the Year grid and exports. This pass
/// runs once at launch: same-day rows collapse into the newest, with
/// their media identifiers merged.
enum JournalMaintenance {
    static func dedupeDuplicates(in context: ModelContext) {
        let descriptor = FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let entries = try? context.fetch(descriptor), entries.count > 1 else { return }
        let grouped = Dictionary(grouping: entries) { DraftStore.dayKey(for: $0.date) }
        var removed = 0
        for (_, sameDay) in grouped where sameDay.count > 1 {
            guard let keep = sameDay.first else { continue }
            var seen: Set<String> = []
            var mergedMedia: [String] = []
            for id in sameDay.flatMap(\.mediaLocalIds) where seen.insert(id).inserted {
                mergedMedia.append(id)
            }
            keep.mediaLocalIds = mergedMedia
            keep.updatedAt = Date()
            for extra in sameDay.dropFirst() {
                // Newest wins; a duplicate that was favorited promotes the flag.
                if extra.isFavorite { keep.isFavorite = true }
                context.delete(extra)
                removed += 1
            }
        }
        if removed > 0 {
            try? context.save()
            Log.event("App", "dedupe: merged \(removed) duplicate day entries")
        }
    }
}
