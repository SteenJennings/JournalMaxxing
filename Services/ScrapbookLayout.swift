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
        func nextMedia() -> ScrapbookBlock? {
            guard mi < mediaIsVideo.count else { return nil }
            let block = ScrapbookBlock.media(index: mi,
                                             fullWidth: mediaIsVideo[mi],
                                             alignRight: mi % 2 == 0)
            mi += 1
            return block
        }
        if chunks.isEmpty {
            while let m = nextMedia() { out.append(m) }
            return out
        }
        for chunk in chunks {
            out.append(.text(chunk))
            if let m = nextMedia() { out.append(m) }
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
        guard sentences.count > 2 else { return [single] }
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
}
