import XCTest
@testable import Dayline

@MainActor
final class PhotoServiceTests: XCTestCase {
    func testSuggestEmptyWhenNoPhotos() {
        let service = PhotoService()
        // Initially empty, should return empty
        XCTAssertTrue(service.suggest(for: "beach").isEmpty)
    }
}
