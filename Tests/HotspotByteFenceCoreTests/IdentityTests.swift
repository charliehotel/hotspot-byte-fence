import XCTest
@testable import HotspotByteFenceCore

final class IdentityTests: XCTestCase {
    func testManualIdentityUsesCanonicalHexForms() throws {
        let ssid = try SSID(hex: "486f742d53706f74")
        let bssid = try BSSID(string: "AA:bb:00:11:22:CC")

        XCTAssertEqual(ssid.hex, "486f742d53706f74")
        XCTAssertEqual(bssid.description, "aa:bb:00:11:22:cc")
    }

    func testManualIdentityRejectsMalformedValues() {
        XCTAssertThrowsError(try SSID(hex: "abc"))
        XCTAssertThrowsError(try SSID(hex: "00" + String(repeating: "00", count: 32)))
        XCTAssertThrowsError(try BSSID(string: "aa:bb:cc:dd:ee"))
        XCTAssertThrowsError(try BSSID(string: "aa:bb:cc:dd:ee:gg"))
    }

    func testNetworkIdentityRequiresAConfirmedBSSID() throws {
        XCTAssertThrowsError(try NetworkIdentity(
            ssid: SSID(hex: "0102"),
            interfaceName: "en0",
            confirmedBSSIDs: []
        )) { error in
            XCTAssertEqual(error as? IdentityError, .emptyBSSIDSet)
        }
    }

    func testAliasTrimsAndNormalizesNFC() throws {
        let alias = try ProfileAlias("  Cafe\u{301}  ")

        XCTAssertEqual(alias.value, "Café")
    }

    func testStableSnapshotRequiresByteForByteEquality() throws {
        let first = try makeSnapshot(bssid: "aa:bb:cc:dd:ee:ff")
        let second = try makeSnapshot(bssid: "aa:bb:cc:dd:ee:ff")
        let changed = try makeSnapshot(bssid: "aa:bb:cc:dd:ee:00")

        XCTAssertEqual(try StableIdentitySnapshot.requireEqual(first, second), first)
        XCTAssertThrowsError(try StableIdentitySnapshot.requireEqual(first, changed))
    }

    func testResolverIgnoresUnregisteredInterfacesAndReportsMultipleTargets() throws {
        let first = try profile(alias: "SIM 1", ssid: "0102", bssid: "aa:bb:cc:dd:ee:01", interfaceName: "en0")
        let second = try profile(alias: "SIM 2", ssid: "0304", bssid: "aa:bb:cc:dd:ee:02", interfaceName: "en1")
        let firstSnapshot = try makeSnapshot(ssid: "0102", bssid: "aa:bb:cc:dd:ee:01", interfaceName: "en0")
        let secondSnapshot = try makeSnapshot(ssid: "0304", bssid: "aa:bb:cc:dd:ee:02", interfaceName: "en1")

        let result = ProfileResolver.resolve(
            profiles: [first, second],
            snapshots: [firstSnapshot, secondSnapshot]
        )

        XCTAssertEqual(result, .multipleProfilesConnected([first.id, second.id]))
    }

    func testResolverRequiresBSSIDConfirmationForNewBSSID() throws {
        let profile = try self.profile(alias: "SIM 1", ssid: "0102", bssid: "aa:bb:cc:dd:ee:01")
        let snapshot = try makeSnapshot(ssid: "0102", bssid: "aa:bb:cc:dd:ee:02")

        XCTAssertEqual(
            ProfileResolver.resolve(profiles: [profile], snapshots: [snapshot]),
            .needsBSSIDConfirmation([profile.id])
        )
    }

    func testResolverDoesNotIgnoreASecondUnconfirmedTarget() throws {
        let first = try profile(alias: "SIM 1", ssid: "0102", bssid: "aa:bb:cc:dd:ee:01", interfaceName: "en0")
        let second = try profile(alias: "SIM 2", ssid: "0304", bssid: "aa:bb:cc:dd:ee:02", interfaceName: "en1")
        let firstSnapshot = try makeSnapshot(ssid: "0102", bssid: "aa:bb:cc:dd:ee:01", interfaceName: "en0")
        let secondSnapshot = try makeSnapshot(ssid: "0304", bssid: "aa:bb:cc:dd:ee:03", interfaceName: "en1")

        XCTAssertEqual(
            ProfileResolver.resolve(
                profiles: [first, second],
                snapshots: [firstSnapshot, secondSnapshot]
            ),
            .needsBSSIDConfirmation([second.id])
        )
    }

    private func profile(
        alias: String,
        ssid: String,
        bssid: String,
        interfaceName: String = "en0"
    ) throws -> ProfileDefinition {
        ProfileDefinition(
            id: ProfileID(),
            alias: try ProfileAlias(alias),
            identity: try NetworkIdentity(
                ssid: SSID(hex: ssid),
                interfaceName: interfaceName,
                confirmedBSSIDs: [BSSID(string: bssid)]
            )
        )
    }

    private func makeSnapshot(
        ssid: String = "0102",
        bssid: String,
        interfaceName: String = "en0"
    ) throws -> WiFiIdentitySnapshot {
        WiFiIdentitySnapshot(
            interfaceName: interfaceName,
            interfaceIndex: interfaceName == "en0" ? 4 : 5,
            linkState: .associated,
            ssid: try SSID(hex: ssid),
            bssid: try BSSID(string: bssid)
        )
    }

    func testFXIdentity001FixtureValidation() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)

        for item in fixture.validSSIDs {
            let ssid = try SSID(hex: item.hex)
            XCTAssertEqual(ssid.hex, item.hex.lowercased())
            XCTAssertEqual(ssid.bytes.count, item.byteCount)
            if let expectedUTF8 = item.utf8 {
                XCTAssertEqual(String(bytes: ssid.bytes, encoding: .utf8), expectedUTF8)
            }
        }

        for item in fixture.invalidSSIDs {
            XCTAssertThrowsError(try SSID(hex: item.hex), "Expected failure for \(item.name)")
        }

        for item in fixture.validBSSIDs {
            let bssid = try BSSID(string: item.input)
            XCTAssertEqual(bssid.description, item.normalized.lowercased())
        }

        for item in fixture.invalidBSSIDs {
            XCTAssertThrowsError(try BSSID(string: item.input), "Expected failure for \(item.reason)")
        }

        let baseProfile = try profile(
            alias: "Target Hotspot",
            ssid: "486f7473706f74",
            bssid: "aa:bb:cc:dd:ee:01",
            interfaceName: "en0"
        )

        for testCase in fixture.resolutionCases {
            let snapshots: [WiFiIdentitySnapshot] = try testCase.snapshots.map { snap in
                let linkState: WiFiLinkState = snap.linkState == "associated" ? .associated : .notAssociated
                return WiFiIdentitySnapshot(
                    interfaceName: snap.interfaceName,
                    interfaceIndex: snap.interfaceIndex,
                    linkState: linkState,
                    ssid: try SSID(hex: snap.ssidHex),
                    bssid: try BSSID(string: snap.bssid)
                )
            }
            let result = ProfileResolver.resolve(profiles: [baseProfile], snapshots: snapshots)
            switch testCase.expectedResolution {
            case "connected":
                XCTAssertEqual(result, .connected(baseProfile.id), "Case: \(testCase.caseID)")
            case "needsBSSIDConfirmation":
                XCTAssertEqual(result, .needsBSSIDConfirmation([baseProfile.id]), "Case: \(testCase.caseID)")
            case "unknownNetwork":
                XCTAssertEqual(result, .unknownNetwork, "Case: \(testCase.caseID)")
            case "disconnected":
                XCTAssertEqual(result, .disconnected, "Case: \(testCase.caseID)")
            default:
                XCTFail("Unknown expected resolution: \(testCase.expectedResolution)")
            }
        }
    }

    private func loadFixture() throws -> IdentityFixture {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "FX-Identity-001",
            withExtension: "json",
            subdirectory: "Fixtures/HotspotByteFence"
        ))
        return try JSONDecoder().decode(IdentityFixture.self, from: Data(contentsOf: url))
    }
}

private struct IdentityFixture: Decodable {
    struct ValidSSID: Decodable {
        let name: String
        let hex: String
        let utf8: String?
        let byteCount: Int
    }
    struct InvalidSSID: Decodable {
        let name: String
        let hex: String
        let reason: String
    }
    struct ValidBSSID: Decodable {
        let input: String
        let normalized: String
    }
    struct InvalidBSSID: Decodable {
        let input: String
        let reason: String
    }
    struct SnapshotItem: Decodable {
        let bssid: String
        let interfaceIndex: UInt32
        let interfaceName: String
        let linkState: String
        let ssidHex: String
    }
    struct ResolutionCase: Decodable {
        let caseID: String
        let description: String
        let expectedResolution: String
        let snapshots: [SnapshotItem]
    }

    let schemaVersion: Int
    let validSSIDs: [ValidSSID]
    let invalidSSIDs: [InvalidSSID]
    let validBSSIDs: [ValidBSSID]
    let invalidBSSIDs: [InvalidBSSID]
    let resolutionCases: [ResolutionCase]
}
