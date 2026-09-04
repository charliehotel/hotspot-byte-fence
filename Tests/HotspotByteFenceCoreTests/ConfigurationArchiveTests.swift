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

    func testFXConfigurationArchive001FixtureValidation() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)

        for valid in fixture.validArchives {
            let profiles = try valid.profiles.map { profile in
                try CWNetworkProfileArchiveV1(
                    ssidHex: profile.ssidHex,
                    securityRawValue: DecimalUInt64(rawValue: profile.securityRawValue)
                )
            }
            let archive = CWConfigurationArchiveV1(
                networkProfiles: profiles,
                flags: valid.flags
            )
            let canonicalData = try archive.canonicalData()
            XCTAssertEqual(String(decoding: canonicalData, as: UTF8.self), valid.expectedCanonicalJSON)
            let roundTrip = try CWConfigurationArchiveV1(canonicalData: canonicalData)
            XCTAssertEqual(roundTrip, archive)
        }

        for invalid in fixture.invalidProfileCases {
            XCTAssertThrowsError(try CWNetworkProfileArchiveV1(
                ssidHex: invalid.ssidHex,
                securityRawValue: DecimalUInt64(rawValue: invalid.securityRawValue)
            ))
        }

        for replay in fixture.replayCases {
            let initialProfiles = try replay.initialProfiles.map { profile in
                try CWNetworkProfileArchiveV1(
                    ssidHex: profile.ssidHex,
                    securityRawValue: DecimalUInt64(rawValue: profile.securityRawValue)
                )
            }
            let archive = CWConfigurationArchiveV1(
                networkProfiles: initialProfiles,
                flags: CWConfigurationArchiveFlagsV1(
                    requireAdministratorForAssociation: false,
                    requireAdministratorForIBSSMode: false,
                    requireAdministratorForPower: false,
                    rememberJoinedNetworks: true
                )
            )
            let result = archive.removingProfiles(matching: try SSID(hex: replay.removeSSIDHex))
            XCTAssertEqual(result.networkProfiles.map { $0.ssidHex }, replay.expectedRemainingProfiles.map { $0.ssidHex })
        }
    }

    private func loadFixture() throws -> ConfigurationArchiveFixture {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "FX-ConfigurationArchive-001",
            withExtension: "json",
            subdirectory: "Fixtures/HotspotByteFence"
        ))
        return try JSONDecoder().decode(ConfigurationArchiveFixture.self, from: Data(contentsOf: url))
    }
}

private struct ConfigurationArchiveFixture: Decodable {
    struct ValidArchive: Decodable {
        let caseID: String
        let description: String
        let flags: CWConfigurationArchiveFlagsV1
        let profiles: [ProfileItem]
        let expectedCanonicalJSON: String
    }
    struct ProfileItem: Decodable {
        let securityRawValue: UInt64
        let ssidHex: String

        enum CodingKeys: String, CodingKey {
            case securityRawValue
            case ssidHex
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let rawValueString = try container.decode(String.self, forKey: .securityRawValue)
            guard let rawValue = UInt64(rawValueString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .securityRawValue,
                    in: container,
                    debugDescription: "Invalid securityRawValue"
                )
            }
            self.securityRawValue = rawValue
            self.ssidHex = try container.decode(String.self, forKey: .ssidHex)
        }
    }
    struct InvalidProfileCase: Decodable {
        let description: String
        let securityRawValue: UInt64
        let ssidHex: String
        let expectedError: String

        enum CodingKeys: String, CodingKey {
            case description
            case securityRawValue
            case ssidHex
            case expectedError
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.description = try container.decode(String.self, forKey: .description)
            let rawValueString = try container.decode(String.self, forKey: .securityRawValue)
            guard let rawValue = UInt64(rawValueString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .securityRawValue,
                    in: container,
                    debugDescription: "Invalid securityRawValue"
                )
            }
            self.securityRawValue = rawValue
            self.ssidHex = try container.decode(String.self, forKey: .ssidHex)
            self.expectedError = try container.decode(String.self, forKey: .expectedError)
        }
    }
    struct ReplayCase: Decodable {
        let caseID: String
        let description: String
        let removeSSIDHex: String
        let initialProfiles: [ProfileItem]
        let expectedRemainingProfiles: [ProfileItem]
    }

    let schemaVersion: Int
    let validArchives: [ValidArchive]
    let invalidProfileCases: [InvalidProfileCase]
    let replayCases: [ReplayCase]
}
