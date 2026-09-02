import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class NumericTests: XCTestCase {
    func testLimitParserStoresExactHundredthGB() throws {
        let minimum = try DataLimitParser.parse("0.01", decimalSeparator: ".")
        let maximum = try DataLimitParser.parse("1000", decimalSeparator: ".")

        XCTAssertEqual(minimum.bytes, ByteCount(10_000_000))
        XCTAssertEqual(maximum.bytes, ByteCount(1_000_000_000_000))
    }

    func testLimitParserRejectsNonCanonicalInput() {
        let invalidValues = ["0", "0.001", "1,000", "+1", "1e1", "1.2.3", " 1", "1 ", "1."]

        for value in invalidValues {
            XCTAssertThrowsError(try DataLimitParser.parse(value, decimalSeparator: "."), value)
        }
    }

    func testLimitParserUsesOnlyEffectiveSeparator() {
        XCTAssertNoThrow(try DataLimitParser.parse("4,50", decimalSeparator: ","))
        XCTAssertThrowsError(try DataLimitParser.parse("4.50", decimalSeparator: ","))
    }

    func testUsageFormatterUsesHalfUpRoundingAndFixedSuffix() throws {
        XCTAssertEqual(try UsageFormatter.format(ByteCount(4_500_000_000)), "4.50GB")
        XCTAssertEqual(try UsageFormatter.format(ByteCount(4_505_000_000)), "4.51GB")
    }

    func testUsageBandUsesExactByteThresholds() throws {
        let limit = try DataLimitParser.parse("4.50", decimalSeparator: ".")

        XCTAssertEqual(UsageBand.forUsage(ByteCount(2_250_000_000), limit: limit), .notice)
        XCTAssertEqual(UsageBand.forUsage(ByteCount(3_600_000_000), limit: limit), .warning)
        XCTAssertEqual(UsageBand.forUsage(ByteCount(4_050_000_000), limit: limit), .critical)
        XCTAssertEqual(UsageBand.forUsage(ByteCount(4_500_000_000), limit: limit), .limitReached)
    }

    func testPersistedUnsignedValuesUseCanonicalDecimalStrings() throws {
        let snapshot = CounterSnapshot(rx: 4_000_000_000, tx: 5_000_000_000)
        let limit = try DataLimitParser.parse("4.50")

        XCTAssertEqual(
            String(decoding: try StoreJSONCodec.encode(snapshot), as: UTF8.self),
            "{\"rx\":\"4000000000\",\"tx\":\"5000000000\"}"
        )
        XCTAssertEqual(
            String(decoding: try StoreJSONCodec.encode(limit), as: UTF8.self),
            "\"450\""
        )
    }

    func testPersistedUnsignedValuesRejectLeadingZeros() {
        XCTAssertThrowsError(try DecimalUInt64(decimalString: "01"))
        XCTAssertThrowsError(try StoreJSONCodec.decode(ByteCount.self, from: Data("\"01\"".utf8)))
    }
}
