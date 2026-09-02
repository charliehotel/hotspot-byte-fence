import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class ProfilePersistenceTests: XCTestCase {
    func testCompleteProfileRoundTripsRawIdentityAndCanonicalFields() throws {
        let profile = try makeProfile()
        let encoded = try StoreJSONCodec.encode(profile)
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(try StoreJSONCodec.decode(ProfileRecord.self, from: encoded), profile)
        XCTAssertEqual(profile.aliasNFC, "SIM Café")
        XCTAssertEqual(profile.ssidHex, "0102")
        XCTAssertEqual(profile.confirmedBSSIDs.map(\.description), [
            "aa:bb:cc:dd:ee:01",
            "aa:bb:cc:dd:ee:02"
        ])
        XCTAssertTrue(json.contains("\"aliasNFC\":\"SIM Café\""))
        XCTAssertTrue(json.contains("\"limitBytes\":\"10000000\""))
        XCTAssertFalse(json.contains("processAuthorizationAvailable"))
    }

    func testIncompleteProfileUsesExplicitNullableIdentityFields() throws {
        let profile = try makeProfile(
            ssidHex: nil,
            interfaceName: nil,
            confirmedBSSIDs: [],
            isComplete: false
        )
        let json = String(decoding: try StoreJSONCodec.encode(profile), as: UTF8.self)

        XCTAssertNil(profile.ssidHex)
        XCTAssertNil(profile.interfaceName)
        XCTAssertTrue(json.contains("\"ssidHex\":null"))
        XCTAssertTrue(json.contains("\"interfaceName\":null"))
        XCTAssertEqual(
            try StoreJSONCodec.decode(ProfileRecord.self, from: Data(json.utf8)),
            profile
        )
    }

    func testProfileRejectsInvalidCompletionLimitAndDateOrder() throws {
        XCTAssertThrowsError(try makeProfile(limitBytes: ByteCount(9_999_999))) { error in
            XCTAssertEqual(error as? ProfileRecordValidationError, .invalidLimit)
        }
        XCTAssertThrowsError(try makeProfile(isComplete: false)) { error in
            XCTAssertEqual(error as? ProfileRecordValidationError, .invalidCompletion)
        }
        XCTAssertThrowsError(
            try makeProfile(
                createdAt: Date(timeIntervalSince1970: 20),
                updatedAt: Date(timeIntervalSince1970: 10)
            )
        ) { error in
            XCTAssertEqual(error as? ProfileRecordValidationError, .invalidDates)
        }
    }

    func testMeasurementRequiresAnAllOrNothingTrustedBaseline() throws {
        let identity = try makeIdentitySnapshot(profileID: UUID())

        XCTAssertThrowsError(
            try MeasurementRecord(
                usageBytes: ByteCount(0),
                baselinePending: false,
                lastTrustedIdentity: nil,
                lastRXBytes: nil,
                lastTXBytes: nil,
                lastSampleWallClock: nil,
                lastPersistedUsageAt: Date(timeIntervalSince1970: 10),
                bytesSinceLastFlush: ByteCount(0)
            )
        ) { error in
            XCTAssertEqual(error as? ProfileRecordValidationError, .invalidMeasurementState)
        }

        let measurement = try MeasurementRecord(
            usageBytes: ByteCount(100),
            baselinePending: false,
            lastTrustedIdentity: identity,
            lastRXBytes: DecimalUInt64(rawValue: 40),
            lastTXBytes: DecimalUInt64(rawValue: 60),
            lastSampleWallClock: Date(timeIntervalSince1970: 10),
            lastPersistedUsageAt: Date(timeIntervalSince1970: 10),
            bytesSinceLastFlush: ByteCount(100)
        )
        let json = String(decoding: try StoreJSONCodec.encode(measurement), as: UTF8.self)

        XCTAssertTrue(json.contains("\"lastRXBytes\":\"40\""))
        XCTAssertTrue(json.contains("\"lastTXBytes\":\"60\""))
    }

    func testVerifiedObservationRequiresEventBackedCoverage() throws {
        XCTAssertThrowsError(
            try ObservationSummaryRecord(
                result: .verified,
                source: .pollBacked,
                awakeSecondsObserved: 30,
                maxGapSeconds: 2,
                targetAbsentAtEnd: true
            )
        ) { error in
            XCTAssertEqual(error as? ProfileRecordValidationError, .invalidObservation)
        }

        let verified = try ObservationSummaryRecord(
            result: .verified,
            source: .eventBacked,
            awakeSecondsObserved: 30,
            maxGapSeconds: 2,
            targetAbsentAtEnd: true
        )
        XCTAssertEqual(verified.result, .verified)
    }

    private func makeProfile(
        profileID: UUID = UUID(),
        ssidHex: String? = "0102",
        interfaceName: String? = "en0",
        confirmedBSSIDs: [BSSID]? = nil,
        isComplete: Bool = true,
        limitBytes: ByteCount = ByteCount(10_000_000),
        createdAt: Date = Date(timeIntervalSince1970: 10),
        updatedAt: Date = Date(timeIntervalSince1970: 20)
    ) throws -> ProfileRecord {
        let bssids: [BSSID]
        if let confirmedBSSIDs {
            bssids = confirmedBSSIDs
        } else {
            bssids = [
                try BSSID(string: "aa:bb:cc:dd:ee:02"),
                try BSSID(string: "aa:bb:cc:dd:ee:01")
            ]
        }
        let identity = try makeIdentitySnapshot(profileID: profileID)
        let measurement = try MeasurementRecord(
            usageBytes: ByteCount(100),
            baselinePending: false,
            lastTrustedIdentity: identity,
            lastRXBytes: DecimalUInt64(rawValue: 40),
            lastTXBytes: DecimalUInt64(rawValue: 60),
            lastSampleWallClock: Date(timeIntervalSince1970: 15),
            lastPersistedUsageAt: Date(timeIntervalSince1970: 15),
            bytesSinceLastFlush: ByteCount(100)
        )
        let protection = try ProtectionRecord(
            limitReached: false,
            pauseBlocking: false,
            blockingCapability: .measurementOnly,
            lastAuthorizationOutcome: .neverRequested,
            retry: RetryRecord(
                state: .none,
                attemptIndex: 0,
                nextEligibleAt: nil,
                lastAttemptAt: nil
            ),
            lastSuppressionObservation: nil,
            lastFailureReason: nil,
            ownedTransactionID: nil
        )
        return try ProfileRecord(
            profileID: profileID,
            aliasNFC: "  SIM Cafe\u{301}  ",
            ssidHex: ssidHex,
            interfaceName: interfaceName,
            confirmedBSSIDs: bssids,
            isComplete: isComplete,
            sharesInterfaceSSID: false,
            limitBytes: limitBytes,
            resetDay: 31,
            cycle: CycleRecord(
                trustedCycleDate: "2026-09-01",
                cycleStartInstant: Date(timeIntervalSince1970: 0),
                timeZoneID: "Asia/Seoul",
                lastTrustedWallClock: Date(timeIntervalSince1970: 15),
                timeAcknowledgementRequired: false
            ),
            measurement: measurement,
            protection: protection,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func makeIdentitySnapshot(profileID: UUID) throws -> IdentitySnapshotRecord {
        try IdentitySnapshotRecord(
            profileID: profileID,
            interfaceName: "en0",
            interfaceIndex: 4,
            linkState: .associated,
            ssidHex: "0102",
            bssid: "aa:bb:cc:dd:ee:01"
        )
    }

}
