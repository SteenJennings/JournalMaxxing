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
}
