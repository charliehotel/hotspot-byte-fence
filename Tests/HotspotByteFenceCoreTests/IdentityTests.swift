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
}
