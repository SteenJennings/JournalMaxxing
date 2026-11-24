import XCTest
@testable import Dayline

final class ScrapbookLayoutTests: XCTestCase {

    private func kinds(_ blocks: [ScrapbookBlock]) -> [String] {
        blocks.map { block in
            switch block {
            case .text: return "t"
            case .media: return "m"
            }
        }
    }

    func testNoMediaTextOnly() {
        let blocks = ScrapbookLayout.blocks(text: "A quiet day.", mediaIsVideo: [])
        XCTAssertEqual(kinds(blocks), ["t"])
    }

    func testNoTextMediaOnly() {
        let blocks = ScrapbookLayout.blocks(text: "  ", mediaIsVideo: [false, true])
        XCTAssertEqual(kinds(blocks), ["m", "m"])
        guard case .media(_, let fullWidth, _) = blocks[1] else { return XCTFail("expected media") }
        XCTAssertTrue(fullWidth, "videos go full width")
    }

    func testParagraphsInterleaveWithMedia() {
        let blocks = ScrapbookLayout.blocks(text: "Para one.\n\nPara two.\n\nPara three.",
                                            mediaIsVideo: [false, false])
        XCTAssertEqual(kinds(blocks), ["t", "m", "t", "m", "t"])
    }

    func testMediaAlignmentAlternates() {
        let blocks = ScrapbookLayout.blocks(text: "Short.", mediaIsVideo: [false, false, false])
        let alignments: [Bool] = blocks.compactMap { block in
            if case .media(_, _, let right) = block { return right }
            return nil
        }
        XCTAssertEqual(alignments, [true, false, true])
    }

    func testTrailingMediaDistributesInsteadOfDumping() {
        // One chunk + three media: the surplus used to pile up after
        // the last chunk. Now it distributes between chunks — with one
        // chunk, all three follow it, in order, videos full width.
        let blocks = ScrapbookLayout.blocks(text: "One para.", mediaIsVideo: [false, false, true])
        XCTAssertEqual(kinds(blocks), ["t", "m", "m", "m"])
        guard case .media(_, let fullWidth, _) = blocks[3] else { return XCTFail("expected media") }
        XCTAssertTrue(fullWidth, "the video block goes full width")
        let alignments: [Bool] = blocks.compactMap { block in
            if case .media(_, _, let right) = block { return right }
            return nil
        }
        // The video does not tuck (full width), so its alignment is
        // false; the two photos alternate right, left.
        XCTAssertEqual(alignments, [true, false, false])
    }

    func testLongTwoSentenceParagraphSplits() {
        // A >240-char paragraph with only two sentences used to stay
        // one chunk and never pepper. Now it splits at word boundaries.
        let part = String(repeating: "the light was unreal over the bay ", count: 8)
        let text = part + ". " + part + "."
        XCTAssertGreaterThan(text.count, 240)
        let chunks = ScrapbookLayout.textChunks(text)
        XCTAssertGreaterThan(chunks.count, 1, "long two-sentence paragraph should split")
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 260 }, "chunks stay near the ~240-char target")
    }

    func testLongSingleParagraphSplitsForPeppering() {
        let sentence = "We walked down to the water and the light was doing something unreal over the bay"
        let text = (0..<6).map { _ in sentence }.joined(separator: ". ") + "."
        let chunks = ScrapbookLayout.textChunks(text)
        XCTAssertGreaterThan(chunks.count, 1, "long paragraph should split into chunks")
        XCTAssertLessThanOrEqual(chunks.count, 4)
        let blocks = ScrapbookLayout.blocks(text: text, mediaIsVideo: [false, false])
        // Media should appear before the final text chunk (peppered, not dumped).
        let lastTextIndex = blocks.lastIndex { if case .text = $0 { return true }; return false }!
        let mediaIndices = blocks.indices.filter { if case .media = blocks[$0] { return true }; return false }
        XCTAssertTrue(mediaIndices.allSatisfy { $0 < lastTextIndex || blocks.count - 1 == $0 },
                      "media should be interspersed through the text")
    }
}
