import SwiftUI
import SwiftData
import Photos

/// Groups entries into months, newest month first. Pure, so it is
/// unit-tested (YearGroupingTests) — the Year grid's structure lives
/// here, not in view code.
struct MonthGroup: Identifiable {
    var id: String { key }
    var key: String // "2026-10"
    var title: String // "October 2026"
    var entries: [DayEntry]
}

enum YearGrouping {
    static func group(_ entries: [DayEntry], calendar: Calendar = .current) -> [MonthGroup] {
        let grouped = Dictionary(grouping: entries) { entry -> String in
            let c = calendar.dateComponents([.year, .month], from: entry.date)
            return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
        }
        return grouped.map { key, entries in
            let sorted = entries.sorted { $0.date > $1.date }
            let title = sorted.first.map { $0.date.formatted(.dateTime.month(.wide).year()) } ?? key
            return MonthGroup(key: key, title: title, entries: sorted)
        }.sorted { $0.key > $1.key }
    }
}

struct TimelineView: View {
    @Query(sort: \DayEntry.date, order: .reverse) var entries: [DayEntry]
    let cols = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    var groups: [MonthGroup] { YearGrouping.group(entries) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.title).font(Theme.display(18)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(group.entries.count) days")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Hairline()
                            LazyVGrid(columns: cols, spacing: 10) {
                                ForEach(group.entries) { e in
                                    NavigationLink { EntryDetailView(entry: e) } label: {
                                        YearCard(entry: e)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.padding()
            }
            .background(Theme.paper)
            .navigationTitle("Year")
            .overlay { if entries.isEmpty { ContentUnavailableView("No entries yet", systemImage: "calendar", description: Text("Start in Today tab")) } }
        }
    }
}

/// One day in the index: the photo fills the top, then a serif date,
/// the first line of the entry, and tags as plain words. Favorites get
/// the rust star — the third and last job of the accent color.
struct YearCard: View {
    var entry: DayEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                TimelineThumbnail(localId: entry.highlightLocalId ?? entry.mediaLocalIds.first)
                    .frame(height: 110)
                if entry.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                        .padding(6)
                }
            }
            Text(entry.date, style: .date)
                .font(.system(size: 11, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(entry.polishedText.isEmpty ? entry.rawTranscript : entry.polishedText)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if !entry.projectTags.isEmpty {
                Text(entry.projectTags.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline, lineWidth: 1))
    }
}

/// Resolves a stored localIdentifier back to a real thumbnail image.
struct TimelineThumbnail: View {
    var localId: String?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.ink.opacity(0.06))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: localId) {
            guard let localId,
                  let asset = AssetMediaLoader.fetchAssets(localIdentifiers: [localId]).first else { return }
            image = await AssetMediaLoader.image(for: asset, targetSize: CGSize(width: 220, height: 220))
        }
    }
}

struct TrendsView: View {
    @Query(sort: \DayEntry.date, order: .reverse) var entries: [DayEntry]
    @StateObject var summarizer = Summarizer()
    @State var summary = ""
    @State var selectedTag: String?
    var tags: [String] { Summarizer.allTags(in: Array(entries)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Theme.kicker("Trends").foregroundStyle(Theme.accent)
                        Text("\(entries.count) days · \(tags.count) tags")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        Hairline().padding(.top, 4)
                    }
                    if tags.isEmpty {
                        Text("No tags yet — tags appear here once entries are polished.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(tags, id: \.self) { tag in
                                Button {
                                    selectedTag = tag
                                    Task { summary = await summarizer.trendSummary(entries: Array(entries), tag: tag) }
                                } label: {
                                    HStack {
                                        Text(tag).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text("\(entries.filter { $0.projectTags.contains(tag) }.count) days")
                                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                                if tag != tags.last { Hairline() }
                            }
                        }
                    }
                    if !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Theme.kicker("Insight — \(selectedTag ?? "")").foregroundStyle(.secondary)
                            Text(summary).font(.body)
                        }
                        .journalCard()
                    }
                }
                .padding()
            }
            .background(Theme.paper)
            .navigationTitle("Trends")
        }
    }
}


/// A past day, opened from the Year grid: its full scrapbook, resolved
/// from the stored photo identifiers.
struct EntryDetailView: View {
    var entry: DayEntry
    @Environment(\.modelContext) private var modelContext
    @State private var assets: [PHAsset] = []
    @State private var showDayBrowser = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Theme.kicker("Dayline").foregroundStyle(Theme.accent)
                    Text(entry.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(Theme.display(22)).foregroundStyle(Theme.ink)
                    if !entry.projectTags.isEmpty || entry.mood != nil {
                        TagLine(tags: entry.projectTags, mood: entry.mood)
                    }
                    Hairline().padding(.top, 4)
                }
                ScrapbookView(text: entry.polishedText.isEmpty ? entry.rawTranscript : entry.polishedText,
                              assets: assets,
                              linkURLs: entry.linkURLs,
                              placeholders: entry.placeholders,
                              heading: "Scrapbook")
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // isFavorite finally has a UI: the model field existed
                // since the scaffold and nothing ever set or read it.
                Button {
                    entry.isFavorite.toggle()
                    entry.updatedAt = Date()
                    try? modelContext.save()
                    Log.event("Entry", "favorite \(entry.isFavorite ? "set" : "cleared") for \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                } label: {
                    Label(entry.isFavorite ? "Unfavorite" : "Favorite",
                          systemImage: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? Theme.accent : Theme.ink)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showDayBrowser = true } label: {
                    Label("Edit photos", systemImage: "photo.on.rectangle.angled")
                }
            }
        }
        .sheet(isPresented: $showDayBrowser) {
            DayMediaBrowserView(date: entry.date,
                                initialSelection: Set(entry.mediaLocalIds)) { chosen in
                entry.mediaLocalIds = chosen.map(\.localIdentifier)
                if let highlight = entry.highlightLocalId, !entry.mediaLocalIds.contains(highlight) {
                    entry.highlightLocalId = entry.mediaLocalIds.first
                }
                entry.updatedAt = Date()
                try? modelContext.save()
                assets = chosen
                Log.event("Browser", "entry media edited via day browser: now \(chosen.count) items")
            }
        }
        .task { assets = AssetMediaLoader.fetchAssets(localIdentifiers: entry.mediaLocalIds) }
    }
}
