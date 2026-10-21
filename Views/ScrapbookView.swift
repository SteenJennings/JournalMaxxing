import SwiftUI
import Photos
import LinkPresentation
import AVKit

struct ScrapbookView: View {
    var text: String
    var assets: [PHAsset]
    var linkURLs: [String] = []
    var placeholders: [Placeholder] = []
    var heading: String = "Scrapbook Preview"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.headline)
            if assets.isEmpty {
                ScrapbookCard {
                    Text(text).font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(assets.enumerated()), id: \.offset) { i, asset in
                    ScrapbookCard {
                        if i == 0 {
                            HStack(alignment: .top, spacing: 12) {
                                Text(text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                    .font(.body)
                                AssetThumbnailView(asset: asset)
                                    .frame(width: 130, height: 100)
                            }
                        } else {
                            // Later cards are media-led: the text lives on the
                            // first card only (an empty text column here was
                            // a layout bug - half-empty cards).
                            AssetThumbnailView(asset: asset)
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                        }
                    }
                }
            }
            ForEach(linkURLs, id: \.self) { urlString in
                if let url = URL(string: urlString) { LinkPreviewView(url: url) }
            }
            ForEach(placeholders.filter { !$0.isResolved }) { p in
                PlaceholderRow(note: p.note, isResolved: p.isResolved)
            }
        }
    }
}

private struct ScrapbookCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

/// Real PHAsset rendering: still image via PHImageManager; a play badge and
/// duration on videos; a Live Photo badge where applicable.
struct AssetThumbnailView: View {
    var asset: PHAsset
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
            if let player {
                VideoPlayer(player: player)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 4) {
                if asset.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                    Text(formatDuration(asset.duration)).font(.caption2)
                }
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                }
            }
            .foregroundColor(.white)
            .padding(4)
            .background(.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(4)
            .opacity(asset.mediaType == .video || asset.mediaSubtypes.contains(.photoLive) ? 1 : 0)
        }
        .task(id: asset.localIdentifier) {
            if asset.mediaType == .video {
                if let item = await AssetMediaLoader.playerItem(for: asset) {
                    let p = AVPlayer(playerItem: item)
                    p.isMuted = true
                    // GIF-like behaviour the design calls for: autoplay
                    // muted and loop. (Observer is per-cell and small in
                    // count; revisit if scrapbooks get long.)
                    loopObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
                        p.seek(to: .zero)
                        p.play()
                    }
                    player = p
                    p.play()
                }
            }
            image = await AssetMediaLoader.image(for: asset, targetSize: CGSize(width: 260, height: 200))
        }
        .onDisappear { player?.pause() }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

/// Real link preview: LPLinkView fed by LPMetadataProvider, with the old
/// placeholder row as fallback while metadata loads or if a site blocks it.
struct LinkPreviewView: View {
    var url: URL
    @State private var metadata: LPLinkMetadata?

    var body: some View {
        Group {
            if let metadata {
                LPLinkViewRepresentable(metadata: metadata)
                    .frame(height: 90)
            } else {
                LinkPreviewRow(url: url.absoluteString)
            }
        }
        .task(id: url.absoluteString) {
            metadata = try? await withCheckedThrowingContinuation { cont in
                LPMetadataProvider().startFetchingMetadata(for: url) { meta, error in
                    if let meta { cont.resume(returning: meta) }
                    else { cont.resume(throwing: error ?? URLError(.unknown)) }
                }
            }
        }
    }
}

private struct LPLinkViewRepresentable: UIViewRepresentable {
    var metadata: LPLinkMetadata
    func makeUIView(context: Context) -> LPLinkView { LPLinkView(metadata: metadata) }
    func updateUIView(_ uiView: LPLinkView, context: Context) { uiView.metadata = metadata }
}

struct LinkPreviewRow: View {
    var url: String
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 6).fill(.blue.opacity(0.1)).frame(width: 40, height: 40).overlay { Image(systemName: "link") }
            VStack(alignment: .leading) { Text("Link Preview").font(.caption.bold()); Text(url).font(.caption2).foregroundStyle(.secondary) }
        }.padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PlaceholderRow: View {
    var note: String
    var isResolved: Bool
    var body: some View {
        Label(note, systemImage: isResolved ? "checkmark.circle.fill" : "exclamationmark.circle").font(.caption).padding().background(.yellow.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
