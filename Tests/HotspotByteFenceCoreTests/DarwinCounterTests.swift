#if canImport(Darwin)
import Darwin
import XCTest
@testable import HotspotByteFenceCore

final class DarwinCounterTests: XCTestCase {
    func testNetRTInterfaceList2LayoutMatchesTheSDKTypes() throws {
        let layout = try DarwinCounterLayout.netRTInterfaceList2()

        XCTAssertEqual(layout.headerSize, MemoryLayout<if_msghdr2>.size)
        XCTAssertEqual(layout.minimumRecordSize, 4)
        XCTAssertEqual(layout.dataSize, MemoryLayout<if_data64>.size)
        XCTAssertEqual(layout.dataOffset, 32)
        XCTAssertEqual(layout.rxOffset, 64)
        XCTAssertEqual(layout.txOffset, 72)
    }
}
#endif
