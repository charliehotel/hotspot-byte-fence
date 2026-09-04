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

    func testFXClock001FixtureValidation() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)

        for item in fixture.fallbackCases {
            let effective = try CycleCalculator.effectiveResetDay(
                year: item.year,
                month: item.month,
                resetDay: item.configuredResetDay
            )
            XCTAssertEqual(effective, item.expectedEffectiveDay)
        }

        let formatter = ISO8601DateFormatter()
        for item in fixture.boundaryCases {
            let timeZone = try XCTUnwrap(TimeZone(identifier: item.timeZoneID))
            let now = try XCTUnwrap(formatter.date(from: item.nowISO8601))
            let boundary = try CycleCalculator.boundary(for: now, resetDay: item.resetDay, timeZone: timeZone)
            XCTAssertEqual(boundary.effectiveDate, item.expectedEffectiveDate, "Case: \(item.caseID)")
            XCTAssertEqual(boundary.timeZoneID, item.timeZoneID, "Case: \(item.caseID)")
        }

        for invalidDay in fixture.invalidResetDays {
            XCTAssertThrowsError(try CycleCalculator.effectiveResetDay(year: 2026, month: 1, resetDay: invalidDay))
        }
    }

    private func loadFixture() throws -> ClockFixture {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "FX-Clock-001",
            withExtension: "json",
            subdirectory: "Fixtures/HotspotByteFence"
        ))
        return try JSONDecoder().decode(ClockFixture.self, from: Data(contentsOf: url))
    }
}

private struct ClockFixture: Decodable {
    struct FallbackCase: Decodable {
        let year: Int
        let month: Int
        let configuredResetDay: Int
        let expectedEffectiveDay: Int
    }
    struct BoundaryCase: Decodable {
        let caseID: String
        let timeZoneID: String
        let nowISO8601: String
        let resetDay: Int
        let expectedEffectiveDate: String
    }

    let schemaVersion: Int
    let fallbackCases: [FallbackCase]
    let boundaryCases: [BoundaryCase]
    let invalidResetDays: [Int]
}
