import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class CounterParserTests: XCTestCase {
    private let layout = CounterRecordLayout(
        headerSize: 16,
        messageLengthOffset: 0,
        messageTypeOffset: 3,
        interfaceIndexOffset: 8,
        dataOffset: 16,
        dataSize: 16,
        rxOffset: 0,
        txOffset: 8
    )

    func testParserAcceptsMixedRecordsAndReturnsChecked64BitCounters() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        let parser = CounterParser(configuration: CounterParserConfiguration(
            layout: fixture.layout.counterRecordLayout,
            targetInterfaceIndex: 4,
            targetInterfaceName: "en0",
            targetRecordType: 18
        ))
        let buffer = fixture.records.reduce(into: [UInt8]()) { result, item in
            result += record(type: item.type, index: item.index, rx: item.rx.rawValue, tx: item.tx.rawValue)
        }

        let counters = try parser.parse(buffer, interfaceNames: names)

        XCTAssertEqual(counters, fixture.expected.interfaceCounters)
    }

    func testParserRejectsTruncatedAndInvalidMessageLengths() {
        let parser = makeParser()
        let truncated = Array(repeating: UInt8(0), count: layout.headerSize - 1)
        var zeroLength = record(type: 18, index: 4, rx: 1, tx: 1)
        writeUInt16(0, into: &zeroLength, at: layout.messageLengthOffset)
        var shortLength = record(type: 18, index: 4, rx: 1, tx: 1)
        writeUInt16(UInt16(layout.headerSize - 1), into: &shortLength, at: layout.messageLengthOffset)

        XCTAssertThrowsError(try parser.parse(truncated, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .bufferTruncated)
        }
        XCTAssertThrowsError(try parser.parse(zeroLength, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .invalidMessageLength)
        }
        XCTAssertThrowsError(try parser.parse(shortLength, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .invalidMessageLength)
        }
    }

    func testParserRejectsDuplicateTargetAndMissingTarget() {
        let parser = makeParser()
        let duplicate = record(type: 18, index: 4, rx: 1, tx: 1) + record(type: 18, index: 4, rx: 2, tx: 2)
        let missing = record(type: 1, index: 99, rx: 1, tx: 1)

        XCTAssertThrowsError(try parser.parse(duplicate, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .duplicateTarget)
        }
        XCTAssertThrowsError(try parser.parse(missing, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .targetMissing)
        }
    }

    func testParserRejectsIndexNameMismatchAndOutOfRecordData() {
        let parser = makeParser()
        var mismatched = record(type: 18, index: 5, rx: 1, tx: 1)
        var tooShort = record(type: 18, index: 4, rx: 1, tx: 1)
        writeUInt16(UInt16(layout.dataOffset + layout.dataSize - 1), into: &tooShort, at: layout.messageLengthOffset)

        XCTAssertThrowsError(try parser.parse(mismatched, interfaceNames: wrongIndexNames)) { error in
            XCTAssertEqual(error as? CounterParseError, .interfaceMismatch)
        }
        XCTAssertThrowsError(try parser.parse(tooShort, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .dataOutOfBounds)
        }
        writeUInt32(4, into: &mismatched, at: layout.interfaceIndexOffset)
        XCTAssertThrowsError(try parser.parse(mismatched, interfaceNames: mismatchedNames)) { error in
            XCTAssertEqual(error as? CounterParseError, .interfaceMismatch)
        }
    }

    func testParserRejectsRXPlusTXOverflow() {
        let parser = makeParser()
        let buffer = record(type: 18, index: 4, rx: UInt64.max, tx: 1)

        XCTAssertThrowsError(try parser.parse(buffer, interfaceNames: names)) { error in
            XCTAssertEqual(error as? CounterParseError, .counterOverflow)
        }
    }

    func testParserSkipsShorterNonTargetRecordsBeforeTarget() throws {
        let shortRecordLayout = CounterRecordLayout(
            headerSize: 16,
            minimumRecordSize: 8,
            messageLengthOffset: 0,
            messageTypeOffset: 3,
            interfaceIndexOffset: 8,
            dataOffset: 16,
            dataSize: 16,
            rxOffset: 0,
            txOffset: 8
        )
        let parser = CounterParser(configuration: CounterParserConfiguration(
            layout: shortRecordLayout,
            targetInterfaceIndex: 4,
            targetInterfaceName: "en0",
            targetRecordType: 18
        ))
        var shortNonTarget = Array(repeating: UInt8(0), count: 8)
        writeUInt16(8, into: &shortNonTarget, at: 0)
        shortNonTarget[3] = 12
        let target = record(type: 18, index: 4, rx: 10, tx: 20)

        XCTAssertEqual(
            try parser.parse(shortNonTarget + target, interfaceNames: names),
            InterfaceCounters(rx: 10, tx: 20, total: 30)
        )
    }

    private var names: TestInterfaceNames {
        TestInterfaceNames(values: [4: "en0", 5: "en1", 99: "lo0"])
    }

    private var mismatchedNames: TestInterfaceNames {
        TestInterfaceNames(values: [4: "en1"])
    }

    private var wrongIndexNames: TestInterfaceNames {
        TestInterfaceNames(values: [5: "en0"])
    }

    private func makeParser() -> CounterParser {
        CounterParser(configuration: CounterParserConfiguration(
            layout: layout,
            targetInterfaceIndex: 4,
            targetInterfaceName: "en0",
            targetRecordType: 18
        ))
    }

    private func loadFixture() throws -> CounterFixture {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "FX-Counter-001",
            withExtension: "json",
            subdirectory: "Fixtures/HotspotByteFence"
        ))
        return try JSONDecoder().decode(CounterFixture.self, from: Data(contentsOf: url))
    }

    private func record(type: UInt8, index: UInt32, rx: UInt64, tx: UInt64) -> [UInt8] {
        var bytes = Array(repeating: UInt8(0), count: layout.dataOffset + layout.dataSize)
        writeUInt16(UInt16(bytes.count), into: &bytes, at: layout.messageLengthOffset)
        bytes[layout.messageTypeOffset] = type
        writeUInt32(index, into: &bytes, at: layout.interfaceIndexOffset)
        writeUInt64(rx, into: &bytes, at: layout.dataOffset + layout.rxOffset)
        writeUInt64(tx, into: &bytes, at: layout.dataOffset + layout.txOffset)
        return bytes
    }

    private func writeUInt16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xff)
        bytes[offset + 1] = UInt8(value >> 8)
    }

    private func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for index in 0..<4 {
            bytes[offset + index] = UInt8((value >> UInt32(index * 8)) & 0xff)
        }
    }

    private func writeUInt64(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
        for index in 0..<8 {
            bytes[offset + index] = UInt8((value >> UInt64(index * 8)) & 0xff)
        }
    }
}

private struct CounterFixture: Decodable {
    let schemaVersion: UInt
    let layout: Layout
    let records: [Record]
    let expected: Expected

    struct Layout: Decodable {
        let headerSize: Int
        let messageLengthOffset: Int
        let messageTypeOffset: Int
        let interfaceIndexOffset: Int
        let dataOffset: Int
        let dataSize: Int
        let rxOffset: Int
        let txOffset: Int

        var counterRecordLayout: CounterRecordLayout {
            CounterRecordLayout(
                headerSize: headerSize,
                messageLengthOffset: messageLengthOffset,
                messageTypeOffset: messageTypeOffset,
                interfaceIndexOffset: interfaceIndexOffset,
                dataOffset: dataOffset,
                dataSize: dataSize,
                rxOffset: rxOffset,
                txOffset: txOffset
            )
        }
    }

    struct Record: Decodable {
        let type: UInt8
        let index: UInt32
        let rx: DecimalUInt64
        let tx: DecimalUInt64
    }

    struct Expected: Decodable {
        let rx: DecimalUInt64
        let tx: DecimalUInt64
        let total: DecimalUInt64

        var interfaceCounters: InterfaceCounters {
            InterfaceCounters(rx: rx.rawValue, tx: tx.rawValue, total: total.rawValue)
        }
    }
}

private struct TestInterfaceNames: InterfaceNameResolving {
    let values: [UInt32: String]

    func name(for interfaceIndex: UInt32) -> String? {
        values[interfaceIndex]
    }
}
