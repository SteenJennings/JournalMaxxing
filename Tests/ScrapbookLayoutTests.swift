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
