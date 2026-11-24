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
        // Peppered layout: text chunks and media alternate down the page
        // (ScrapbookLayout decides the sequence; media alternates
        // right/left, videos full width) instead of one text card followed
        // by a photo dump.
        let blocks = ScrapbookLayout.blocks(text: text,
                                            mediaIsVideo: assets.map { $0.mediaType == .video })
        return VStack(alignment: .leading, spacing: 12) {
            Theme.kicker(heading).foregroundStyle(.secondary)
            if blocks.isEmpty {
                ScrapbookCard {
                    Text(text).font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let chunk):
                        ScrapbookCard(ruled: true) {
                            Text(chunk).font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .media(let index, let fullWidth, let alignRight):
                        mediaBlock(asset: assets[index], fullWidth: fullWidth, alignRight: alignRight)
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

extension ScrapbookView {
    /// One peppered media card, tucked to the right or left of the page
    /// (videos ignore the tuck and span full width).
    fileprivate func mediaBlock(asset: PHAsset, fullWidth: Bool, alignRight: Bool) -> some View {
        HStack(spacing: 0) {
            if alignRight && !fullWidth { Spacer(minLength: 64) }
            ScrapbookCard {
                AssetThumbnailView(asset: asset)
                    .frame(maxWidth: .infinity)
                    .frame(height: fullWidth ? 230 : 185)
            }
            if !alignRight && !fullWidth { Spacer(minLength: 64) }
        }
    }
}

/// A scrapbook card: paper surface, hairline edge, no shadow.
/// Text chunks carry a short rust tick at the top — the margin mark of
/// a journal, and the only place rust appears inside a page.
private struct ScrapbookCard<Content: View>: View {
    var ruled: Bool = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ruled {
                Rectangle().fill(Theme.accent).frame(width: 28, height: 2)
            }
            content
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
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
            // Prints get a caption, not a pill badge: plain small-caps
            // white text over the photo itself.
            HStack(spacing: 4) {
                if asset.mediaType == .video {
                    Image(systemName: "play.fill")
                    Text(formatDuration(asset.duration))
                }
                if asset.mediaSubtypes.contains(.photoLive) {
                    Image(systemName: "livephoto")
                    Text("LIVE")
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
            .padding(6)
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
            RoundedRectangle(cornerRadius: 6).fill(Theme.ink.opacity(0.06)).frame(width: 40, height: 40)
                .overlay { Image(systemName: "link").foregroundStyle(Theme.ink) }
            VStack(alignment: .leading) { Text("Link Preview").font(.caption.bold()); Text(url).font(.caption2).foregroundStyle(.secondary) }
        }.journalCard(padding: 10)
    }
}

struct PlaceholderRow: View {
    var note: String
    var isResolved: Bool
    var body: some View {
        Label(note, systemImage: isResolved ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Theme.ink)
            .padding()
            .background(Theme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
