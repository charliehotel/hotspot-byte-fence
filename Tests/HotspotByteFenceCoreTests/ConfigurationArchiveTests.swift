import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class ConfigurationArchiveTests: XCTestCase {
    func testArchivePreservesOrderFlagsAndCanonicalRoundTrip() throws {
        let target = try CWNetworkProfileArchiveV1(
            ssidHex: "0102",
            securityRawValue: DecimalUInt64(rawValue: 3)
        )
        let unrelated = try CWNetworkProfileArchiveV1(
            ssidHex: "aabbcc",
            securityRawValue: DecimalUInt64(rawValue: 7)
        )
        let flags = CWConfigurationArchiveFlagsV1(
            requireAdministratorForAssociation: true,
            requireAdministratorForIBSSMode: false,
            requireAdministratorForPower: true,
            rememberJoinedNetworks: false
        )
        let archive = CWConfigurationArchiveV1(
            networkProfiles: [target, unrelated],
            flags: flags
        )

        let data = try archive.canonicalData()
        let decoded = try CWConfigurationArchiveV1(canonicalData: data)

        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "{\"networkProfiles\":[{\"securityRawValue\":\"3\",\"ssidHex\":\"0102\"},{\"securityRawValue\":\"7\",\"ssidHex\":\"aabbcc\"}],\"rememberJoinedNetworks\":false,\"requireAdministratorForAssociation\":true,\"requireAdministratorForIBSSMode\":false,\"requireAdministratorForPower\":true,\"schemaVersion\":1}"
        )
        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(decoded.networkProfiles.map(\.ssidHex), ["0102", "aabbcc"])
        XCTAssertEqual(decoded.flags, flags)
        XCTAssertEqual(try CWConfigurationArchiveV1(base64URL: archive.canonicalBase64URL()), archive)
        XCTAssertEqual(CWConfigurationArchiveV1.fingerprintAlgorithm, "hbf-cwconfig-v1-sha256")
        XCTAssertEqual(try archive.fingerprint().count, 64)
    }

    func testArchiveRejectsUnsupportedValues() {
        XCTAssertThrowsError(try CWNetworkProfileArchiveV1(
            ssidHex: "AABB",
            securityRawValue: DecimalUInt64(rawValue: 3)
        )) { error in
            XCTAssertEqual(error as? ConfigurationArchiveError, .invalidSSID)
        }
        XCTAssertThrowsError(try CWNetworkProfileArchiveV1(
            ssidHex: "aabb",
            securityRawValue: DecimalUInt64(rawValue: 16)
        )) { error in
            XCTAssertEqual(error as? ConfigurationArchiveError, .unsupportedSecurityValue)
        }
    }

    func testArchiveRejectsNonCanonicalBytesSchemaAndBase64() throws {
        let archive = CWConfigurationArchiveV1(
            networkProfiles: [],
            flags: CWConfigurationArchiveFlagsV1(
                requireAdministratorForAssociation: false,
                requireAdministratorForIBSSMode: false,
                requireAdministratorForPower: false,
                rememberJoinedNetworks: true
            )
        )
        let canonical = try archive.canonicalData()
        var nonCanonical = Data([UInt8(0x20)])
        nonCanonical.append(canonical)
        nonCanonical.append(UInt8(0x20))
        XCTAssertThrowsError(try CWConfigurationArchiveV1(canonicalData: nonCanonical)) { error in
            XCTAssertEqual(error as? ConfigurationArchiveError, .nonCanonicalArchive)
        }
        let unknownSchema = Data(
            "{\"networkProfiles\":[],\"rememberJoinedNetworks\":true,\"requireAdministratorForAssociation\":false,\"requireAdministratorForIBSSMode\":false,\"requireAdministratorForPower\":false,\"schemaVersion\":2}".utf8
        )
        XCTAssertThrowsError(try CWConfigurationArchiveV1(canonicalData: unknownSchema)) { error in
            XCTAssertEqual(error as? ConfigurationArchiveError, .unsupportedSchemaVersion)
        }
        XCTAssertThrowsError(try CWConfigurationArchiveV1(base64URL: "not valid")) { error in
            XCTAssertEqual(error as? ConfigurationArchiveError, .invalidBase64)
        }
    }

    func testReplayRemovesOnlyMatchingSSIDAndPreservesOrder() throws {
        let firstTarget = try CWNetworkProfileArchiveV1(
            ssidHex: "0102",
            securityRawValue: DecimalUInt64(rawValue: 1)
        )
        let unrelated = try CWNetworkProfileArchiveV1(
            ssidHex: "0304",
            securityRawValue: DecimalUInt64(rawValue: 2)
        )
        let secondTarget = try CWNetworkProfileArchiveV1(
            ssidHex: "0102",
            securityRawValue: DecimalUInt64(rawValue: 9)
        )
        let archive = CWConfigurationArchiveV1(
            networkProfiles: [firstTarget, unrelated, secondTarget],
            flags: CWConfigurationArchiveFlagsV1(
                requireAdministratorForAssociation: true,
                requireAdministratorForIBSSMode: true,
                requireAdministratorForPower: false,
                rememberJoinedNetworks: true
            )
        )

        let replayed = archive.removingProfiles(matching: try SSID(hex: "0102"))

        XCTAssertEqual(replayed.networkProfiles, [unrelated])
        XCTAssertEqual(replayed.flags, archive.flags)
        XCTAssertEqual(archive.removingProfiles(matching: try SSID(hex: "ffff")), archive)
    }
}
