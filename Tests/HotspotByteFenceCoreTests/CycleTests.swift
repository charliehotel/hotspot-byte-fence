import XCTest
@testable import HotspotByteFenceCore

final class CycleTests: XCTestCase {
    func testResetDayFallsBackToLastDayOfMonthWithoutChangingConfiguration() throws {
        XCTAssertEqual(try CycleCalculator.effectiveResetDay(year: 2026, month: 4, resetDay: 31), 30)
        XCTAssertEqual(try CycleCalculator.effectiveResetDay(year: 2026, month: 2, resetDay: 30), 28)
        XCTAssertEqual(try CycleCalculator.effectiveResetDay(year: 2028, month: 2, resetDay: 31), 29)
        XCTAssertEqual(try CycleCalculator.effectiveResetDay(year: 2026, month: 5, resetDay: 31), 31)
    }

    func testCycleUsesTheMostRecentEffectiveLocalResetDate() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))

        let boundary = try CycleCalculator.boundary(for: now, resetDay: 31, timeZone: timeZone)

        XCTAssertEqual(boundary.effectiveDate, "2026-04-30")
        XCTAssertEqual(boundary.timeZoneID, "Asia/Seoul")
    }

    func testResetDayValidationRejectsValuesOutsideOneThroughThirtyOne() {
        XCTAssertThrowsError(try CycleCalculator.effectiveResetDay(year: 2026, month: 1, resetDay: 0))
        XCTAssertThrowsError(try CycleCalculator.effectiveResetDay(year: 2026, month: 1, resetDay: 32))
    }
}
