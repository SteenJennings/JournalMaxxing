import SwiftUI
import SwiftData
import Photos

struct TimelineView: View {
    @Query(sort: \DayEntry.date, order: .reverse) var entries: [DayEntry]
    let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(entries) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            TimelineThumbnail(localId: e.highlightLocalId ?? e.mediaLocalIds.first)
                                .frame(height: 110)
                            Text(e.date, style: .date).font(.caption2).bold()
                            Text(e.polishedText).font(.caption2).lineLimit(2)
                            if !e.projectTags.isEmpty { Text(e.projectTags.map { "#\($0)" }.joined(separator: " ")).font(.caption2).foregroundStyle(.blue) }
                        }.padding(6).background(.background).clipShape(RoundedRectangle(cornerRadius: 8)).shadow(radius: 1)
                    }
                }.padding()
            }.navigationTitle("Year").overlay { if entries.isEmpty { ContentUnavailableView("No entries yet", systemImage: "calendar", description: Text("Start in Today tab")) } }
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
    var tags: [String] {
        let found = Summarizer.allTags(in: Array(entries))
        return found.isEmpty ? ["work", "trip", "building", "family"] : found
    }
    var body: some View {
        NavigationStack {
            List {
                Section("By Tag") {
                    ForEach(tags, id: \.self) { tag in
                        Button(tag) { Task { summary = await summarizer.trendSummary(entries: Array(entries), tag: tag) } }
                    }
                }
                if !summary.isEmpty { Section("Insight") { Text(summary) } }
            }.navigationTitle("Trends")
        }
    }
}
