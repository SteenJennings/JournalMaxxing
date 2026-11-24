import XCTest
@testable import Dayline

final class DiagnosticsLogTests: XCTestCase {
    func testLogRecordsAndExports() {
        let log = DiagnosticsLog(storageURL: nil)
        log.log("Test", "hello world")
        XCTAssertTrue(log.exportText().contains("[Test] hello world"))
    }

    func testClearEmpties() {
        let log = DiagnosticsLog(storageURL: nil)
        log.log("Test", "something")
        log.clear()
        XCTAssertEqual(log.exportText(), "")
    }

    /// The 500-line cap and the drop marker: after 505 lines the export
    /// holds exactly 500 lines, the first is the marker, and the oldest
    /// surviving content line is #7 (the marker consumed #6's slot).
    func testRingBufferCapsAtFiveHundred() {
        let log = DiagnosticsLog(storageURL: nil)
        for i in 1...505 { log.log("Test", "line \(i)") }
        let lines = log.exportText().components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 500)
        XCTAssertTrue(lines[0].contains("dropped"), "first line should be the drop marker, got: \(lines[0])")
        XCTAssertTrue(lines[1].contains("line 7"))
        XCTAssertTrue(lines.last!.contains("line 505"))
    }

    /// Entries survive a relaunch: a second instance over the same file
    /// sees the first instance's lines.
    func testPersistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayline-test-\(UUID().uuidString).log")
        let first = DiagnosticsLog(storageURL: url)
        first.log("Test", "one")
        first.log("Test", "two")
        first.log("Test", "three")
        let second = DiagnosticsLog(storageURL: url)
        XCTAssertTrue(second.exportText().contains("one"))
        XCTAssertTrue(second.exportText().contains("two"))
        XCTAssertTrue(second.exportText().contains("three"))
        try? FileManager.default.removeItem(at: url)
    }

    /// Clear also deletes the file on disk, so a relaunch stays empty.
    func testClearDeletesFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dayline-test-\(UUID().uuidString).log")
        let log = DiagnosticsLog(storageURL: url)
        log.log("Test", "something")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        log.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let reopened = DiagnosticsLog(storageURL: url)
        XCTAssertEqual(reopened.exportText(), "")
    }
}
