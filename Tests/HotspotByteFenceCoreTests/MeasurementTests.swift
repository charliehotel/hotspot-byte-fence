import XCTest
@testable import HotspotByteFenceCore

final class MeasurementTests: XCTestCase {
    func testFirstSampleEstablishesBaselineWithoutAddingUsage() throws {
        var accumulator = MeasurementAccumulator(initialState: state(cycle: "2026-09-01"))

        let outcome = accumulator.ingest(try sample(rx: 100, tx: 50, cycle: "2026-09-01"))

        XCTAssertEqual(outcome, .baselineEstablished)
        XCTAssertEqual(accumulator.state.usageBytes, ByteCount(0))
        XCTAssertEqual(accumulator.state.baseline?.counters, CounterSnapshot(rx: 100, tx: 50))
    }

    func testValidSampleAddsRXAndTXAndRequestsDurableFlush() throws {
        var accumulator = MeasurementAccumulator(initialState: state(cycle: "2026-09-01"))
        _ = accumulator.ingest(try sample(rx: 100, tx: 50, cycle: "2026-09-01"))

        let outcome = accumulator.ingest(try sample(rx: 200, tx: 150, cycle: "2026-09-01"))

        XCTAssertEqual(outcome, .usageAdded(delta: ByteCount(200), persistence: .required))
        XCTAssertEqual(accumulator.state.usageBytes, ByteCount(200))
    }

    func testCounterRegressionRebaselinesWithoutAddingUsage() throws {
        var accumulator = MeasurementAccumulator(initialState: state(cycle: "2026-09-01"))
        _ = accumulator.ingest(try sample(rx: 100, tx: 50, cycle: "2026-09-01"))
        _ = accumulator.ingest(try sample(rx: 200, tx: 150, cycle: "2026-09-01"))

        let outcome = accumulator.ingest(try sample(rx: 10, tx: 20, cycle: "2026-09-01"))

        XCTAssertEqual(outcome, .counterRegression)
        XCTAssertEqual(accumulator.state.usageBytes, ByteCount(200))
        XCTAssertEqual(accumulator.state.baseline?.counters, CounterSnapshot(rx: 10, tx: 20))
    }

    func testCycleChangeDiscardsCrossBoundaryIntervalAndResetsUsage() throws {
        var accumulator = MeasurementAccumulator(initialState: state(cycle: "2026-08-01", usage: 900))
        _ = accumulator.ingest(try sample(rx: 100, tx: 50, cycle: "2026-08-01"))

        let outcome = accumulator.ingest(try sample(rx: 500, tx: 500, cycle: "2026-09-01"))

        XCTAssertEqual(outcome, .cycleChanged)
        XCTAssertEqual(accumulator.state.usageBytes, ByteCount(0))
        XCTAssertEqual(accumulator.state.cycleID.effectiveDate, "2026-09-01")
    }

    func testUsageOverflowPreservesSafeStateAndEntersRecovery() throws {
        var accumulator = MeasurementAccumulator(
            initialState: state(cycle: "2026-09-01", usage: UInt64.max - 10)
        )
        _ = accumulator.ingest(try sample(rx: 100, tx: 100, cycle: "2026-09-01"))

        let outcome = accumulator.ingest(try sample(rx: 200, tx: 200, cycle: "2026-09-01"))

        XCTAssertEqual(outcome, .recoveryRequired(.arithmeticOverflow))
        XCTAssertEqual(accumulator.state.usageBytes, ByteCount(UInt64.max - 10))
        XCTAssertEqual(accumulator.state.status, .recoveryRequired)
    }

    func testFlushMarkerResetsObservedBytesOnlyAfterExplicitDurableConfirmation() throws {
        var accumulator = MeasurementAccumulator(initialState: state(cycle: "2026-09-01"))
        _ = accumulator.ingest(try sample(rx: 100, tx: 50, cycle: "2026-09-01"))
        _ = accumulator.ingest(try sample(rx: 200, tx: 150, cycle: "2026-09-01"))

        XCTAssertEqual(accumulator.state.bytesSinceLastFlush, ByteCount(200))
        accumulator.markDurablyFlushed()
        XCTAssertEqual(accumulator.state.bytesSinceLastFlush, ByteCount(0))
    }

    private func state(cycle: String, usage: UInt64 = 0) -> MeasurementState {
        MeasurementState(
            cycleID: CycleID(effectiveDate: cycle, timeZoneID: "Asia/Seoul"),
            usageBytes: ByteCount(usage)
        )
    }

    private func sample(rx: UInt64, tx: UInt64, cycle: String) throws -> MeasurementSample {
        MeasurementSample(
            identity: WiFiIdentitySnapshot(
                interfaceName: "en0",
                interfaceIndex: 4,
                linkState: .associated,
                ssid: try SSID(hex: "0102"),
                bssid: try BSSID(string: "aa:bb:cc:dd:ee:ff")
            ),
            counters: CounterSnapshot(rx: rx, tx: tx),
            cycleID: CycleID(effectiveDate: cycle, timeZoneID: "Asia/Seoul")
        )
    }
}
