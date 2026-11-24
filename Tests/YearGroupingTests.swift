import XCTest
@testable import Dayline

final class YearGroupingTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testGroupsByMonthNewestFirst() {
        let entries = [
            DayEntry(date: date(2026, 10, 20)),
            DayEntry(date: date(2026, 10, 21)),
            DayEntry(date: date(2026, 9, 3)),
        ]
        let groups = YearGrouping.group(entries)
        XCTAssertEqual(groups.map(\.key), ["2026-10", "2026-09"])
        XCTAssertEqual(groups[0].title, "October 2026")
        XCTAssertEqual(groups[0].entries.count, 2)
        XCTAssertEqual(groups[1].entries.count, 1)
    }

    func testEntriesWithinAMonthAreNewestFirst() {
        let entries = [
            DayEntry(date: date(2026, 10, 2)),
            DayEntry(date: date(2026, 10, 28)),
        ]
        let groups = YearGrouping.group(entries)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].entries[0].date > groups[0].entries[1].date)
    }

    func testEmptyJournalHasNoGroups() {
        XCTAssertTrue(YearGrouping.group([]).isEmpty)
    }
}
