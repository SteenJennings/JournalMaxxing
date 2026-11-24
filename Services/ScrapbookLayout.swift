import Foundation

/// One block in the peppered scrapbook: a chunk of entry text, or one media
/// item. Media alternates alignment (right, left, right...) so photos feel
/// tucked into the page rather than stacked in a gallery; videos always go
/// full width.
enum ScrapbookBlock: Equatable {
    case text(String)
    case media(index: Int, fullWidth: Bool, alignRight: Bool)
}

/// Pure layout builder - kept separate from the view so the interleave rules
/// are unit-testable without Photos or SwiftUI.
enum ScrapbookLayout {
    static func blocks(text: String, mediaIsVideo: [Bool]) -> [ScrapbookBlock] {
        let chunks = textChunks(text)
        var out: [ScrapbookBlock] = []
        var mi = 0
        var photoIndex = 0
        func nextMedia() -> ScrapbookBlock? {
            guard mi < mediaIsVideo.count else { return nil }
            let isVideo = mediaIsVideo[mi]
            // Alignment parity runs on the PHOTO index, not the media
            // index: a video in the middle used to flip every photo
            // after it to the same side.
            let alignRight = isVideo ? false : photoIndex % 2 == 0
            if !isVideo { photoIndex += 1 }
            let block = ScrapbookBlock.media(index: mi, fullWidth: isVideo, alignRight: alignRight)
            mi += 1
            return block
        }
        if chunks.isEmpty {
            while let m = nextMedia() { out.append(m) }
            return out
        }
        // When media outnumber text chunks, distribute the surplus
        // evenly between chunks instead of dumping them all at the end.
        let perChunk = max(1, Int(ceil(Double(mediaIsVideo.count) / Double(chunks.count))))
        for chunk in chunks {
            out.append(.text(chunk))
            for _ in 0..<perChunk {
                guard let m = nextMedia() else { break }
                out.append(m)
            }
        }
        while let m = nextMedia() { out.append(m) }
        return out
    }

    /// Split entry text into chunks for peppering: explicit paragraphs win;
    /// a single long paragraph (> ~240 chars) is split into groups of two
    /// sentences, capped at 4 chunks. Heuristic sentence split on ". " -
    /// abbreviations like "e.g." can split early; cosmetic only.
    static func textChunks(_ text: String) -> [String] {
        let paras = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if paras.count > 1 { return paras }
        guard let single = paras.first else { return [] }
        guard single.count > 240 else { return [single] }
        let sentences = single.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // A long paragraph with only one or two sentences used to stay
        // one chunk — and peppering silently never happened. Split it
        // into ~240-char word-boundary chunks instead.
        guard sentences.count > 2 else { return splitLongText(single) }
        // (splitLongText is the fallback for long paragraphs with too
        // few sentences to group — see above.)
        let groupSize = max(2, Int(ceil(Double(sentences.count) / 4.0)))
        var chunks: [String] = []
        var i = 0
        while i < sentences.count {
            let group = Array(sentences[i..<min(i + groupSize, sentences.count)])
            var chunk = group.joined(separator: ". ")
            if i + groupSize < sentences.count && !chunk.hasSuffix(".") { chunk += "." }
            chunks.append(chunk)
            i += groupSize
        }
        return chunks
    }

    /// Split a long run of text into ~240-char chunks at word boundaries.
    /// Used when a paragraph is long but has too few sentences to group.
    static func splitLongText(_ text: String, maxChars: Int = 240) -> [String] {
        var chunks: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty { current = String(word) }
            else if current.count + 1 + word.count <= maxChars { current += " " + word }
            else { chunks.append(current); current = String(word) }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [text] : chunks
    }
}
