import SwiftUI
import Photos

/// Browse everything shot on a day - photos, videos, Live Photos - and pull
/// items into (or out of) the entry by tapping. Auto-suggestions are the
/// default; this is the manual override Steen asked for: "go in and look at
/// photos on this day, go through, and just pull that sort of stuff in."
struct DayMediaBrowserView: View {
    var date: Date
    var initialSelection: Set<String>
    var onDone: ([PHAsset]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pool: [PHAsset] = []
    @State private var selection: Set<String> = []
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 3)]

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView("Loading this day...")
                } else if pool.isEmpty {
                    ContentUnavailableView("Nothing shot this day",
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text("No photos or videos in your library for \(date.formatted(date: .abbreviated, time: .omitted))."))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(pool.count) items - \(selection.count) in your entry. Tap to add or remove.")
                                .font(.caption).foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(pool, id: \.localIdentifier) { asset in
                                    BrowserTile(asset: asset,
                                                isSelected: selection.contains(asset.localIdentifier))
                                        .onTapGesture {
                                            if selection.contains(asset.localIdentifier) {
                                                selection.remove(asset.localIdentifier)
                                            } else {
                                                selection.insert(asset.localIdentifier)
                                            }
                                        }
                                }
                            }
                        }.padding(10)
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use \(selection.count)") {
                        let chosen = pool.filter { selection.contains($0.localIdentifier) }
                        Log.event("Browser", "day browser confirmed \(chosen.count) of \(pool.count) items for \(date.formatted(date: .abbreviated, time: .omitted))")
                        onDone(chosen)
                        dismiss()
                    }.bold()
                }
            }
            .task {
                selection = initialSelection
                pool = await PhotoService.assets(on: date)
                loaded = true
            }
        }
    }
}

/// Lightweight grid tile: a still poster frame (no live players in a grid),
/// a play badge + duration on videos, a Live Photo badge, and a selection
/// check in the corner.
private struct BrowserTile: View {
    var asset: PHAsset
    var isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.15))
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 3) {
                if asset.mediaType == .video {
                    Image(systemName: "play.fill")
                    Text(formatDuration(asset.duration))
                }
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                }
            }
            .font(.caption2).foregroundStyle(.white)
            .padding(3)
            .background(.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
            .opacity(asset.mediaType == .video || asset.mediaSubtypes.contains(.photoLive) ? 1 : 0)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : .white)
                .shadow(color: .black.opacity(0.35), radius: 2)
                .padding(5)
        }
        .overlay {
            if isSelected {
                Rectangle().stroke(Theme.accent, lineWidth: 3)
            }
        }
        .contentShape(Rectangle())
        .task(id: asset.localIdentifier) {
            image = await AssetMediaLoader.image(for: asset, targetSize: CGSize(width: 220, height: 220))
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
