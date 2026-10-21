import SwiftUI
import SwiftData
import Photos

struct TimelineView: View {
    @Query(sort: \DayEntry.date, order: .reverse) var entries: [DayEntry]
    let cols = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(entries) { e in
                      NavigationLink { EntryDetailView(entry: e) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            TimelineThumbnail(localId: e.highlightLocalId ?? e.mediaLocalIds.first)
                                .frame(height: 110)
                            Text(e.date, style: .date).font(.system(size: 11, weight: .bold, design: .serif))
                            Text(e.polishedText).font(.caption2).lineLimit(2)
                            if !e.projectTags.isEmpty { Text(e.projectTags.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.blue) }
                        }.padding(8).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                      }.buttonStyle(.plain)
                    }
                }.padding()
            }.background(Theme.paper).navigationTitle("Year").overlay { if entries.isEmpty { ContentUnavailableView("No entries yet", systemImage: "calendar", description: Text("Start in Today tab")) } }
        }
    }
}

/// Resolves a stored localIdentifier back to a real thumbnail image.
struct TimelineThumbnail: View {
    var localId: String?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.15))
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
    var tags: [String] { Summarizer.allTags(in: Array(entries)) }
    var body: some View {
        NavigationStack {
            List {
                Section("By Tag") {
                    if tags.isEmpty {
                        Text("No tags yet - tags appear here once entries are polished.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(tags, id: \.self) { tag in
                        Button { Task { summary = await summarizer.trendSummary(entries: Array(entries), tag: tag) } } label: {
                            HStack {
                                Text(tag).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(entries.filter { $0.projectTags.contains(tag) }.count) days")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !summary.isEmpty { Section("Insight") { Text(summary) } }
            }.scrollContentBackground(.hidden).background(Theme.paper).navigationTitle("Trends")
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
            ScrapbookView(text: entry.polishedText.isEmpty ? entry.rawTranscript : entry.polishedText,
                          assets: assets,
                          linkURLs: entry.linkURLs,
                          placeholders: entry.placeholders,
                          heading: "Scrapbook")
                .padding()
        }
        .background(Theme.paper)
        .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted))
        .toolbar {
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
