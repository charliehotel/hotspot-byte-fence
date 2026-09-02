import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class StoreStateRecordTests: XCTestCase {
    func testGlobalStateRoundTripsExplicitNullableFields() throws {
        let normal = try GlobalStateRecord(
            safetyState: .normal,
            recoveryReason: nil,
            timeAdjustment: nil,
            counterCapability: .pending,
            identityCapability: .pending
        )
        let normalJSON = String(decoding: try StoreJSONCodec.encode(normal), as: UTF8.self)

        XCTAssertEqual(try StoreJSONCodec.decode(GlobalStateRecord.self, from: Data(normalJSON.utf8)), normal)
        XCTAssertTrue(normalJSON.contains("\"recoveryReason\":null"))
        XCTAssertTrue(normalJSON.contains("\"timeAdjustment\":null"))

        let adjustment = try TimeAdjustmentRecord(
            reason: .backwardWallClock,
            trustedCycleDate: "2026-09-01",
            observedCycleDate: "2026-08-31",
            timeZoneID: "Asia/Seoul",
            observedAt: Date(timeIntervalSince1970: 10),
            acknowledgementRequired: true
        )
        let blocked = try GlobalStateRecord(
            safetyState: .timeAdjustmentRequired,
            recoveryReason: nil,
            timeAdjustment: adjustment,
            counterCapability: .passed,
            identityCapability: .passed
        )

        XCTAssertEqual(
            try StoreJSONCodec.decode(
                GlobalStateRecord.self,
                from: StoreJSONCodec.encode(blocked)
            ),
            blocked
        )
    }

    func testGlobalStateRejectsInconsistentSafetyDetails() throws {
        XCTAssertThrowsError(
            try GlobalStateRecord(
                safetyState: .normal,
                recoveryReason: .corruptStore,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            )
        ) { error in
            XCTAssertEqual(error as? GlobalStateRecordValidationError, .invalidRecoveryReason)
        }

        XCTAssertThrowsError(
            try GlobalStateRecord(
                safetyState: .recoveryRequired,
                recoveryReason: nil,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            )
        ) { error in
            XCTAssertEqual(error as? GlobalStateRecordValidationError, .invalidRecoveryReason)
        }

        let adjustment = try TimeAdjustmentRecord(
            reason: .earlierCycle,
            trustedCycleDate: "2026-09-01",
            observedCycleDate: "2026-08-01",
            timeZoneID: "Asia/Seoul",
            observedAt: Date(timeIntervalSince1970: 10),
            acknowledgementRequired: false
        )
        XCTAssertThrowsError(
            try GlobalStateRecord(
                safetyState: .timeAdjustmentRequired,
                recoveryReason: nil,
                timeAdjustment: adjustment,
                counterCapability: .pending,
                identityCapability: .pending
            )
        ) { error in
            XCTAssertEqual(error as? GlobalStateRecordValidationError, .invalidTimeAdjustment)
        }
    }

    func testIntegrityRoundTripsExplicitNullableFieldsAndRevision() throws {
        let integrity = try IntegrityRecord(
            canonicalDigest: String(repeating: "a", count: 64),
            lkgDigest: nil,
            lastValidatedRevision: DecimalUInt64(rawValue: 2),
            previousValidatedRevision: DecimalUInt64(rawValue: 1),
            validatedAt: Date(timeIntervalSince1970: 20)
        )
        let encoded = try StoreJSONCodec.encode(integrity)
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(try StoreJSONCodec.decode(IntegrityRecord.self, from: encoded), integrity)
        XCTAssertTrue(json.contains("\"algorithm\":\"hbf-store-v1-sha256\""))
        XCTAssertTrue(json.contains("\"lkgDigest\":null"))
        XCTAssertTrue(json.contains("\"previousValidatedRevision\":\"1\""))
    }

    func testIntegrityRejectsInvalidAlgorithmDigestAndRevision() throws {
        XCTAssertThrowsError(
            try IntegrityRecord(
                algorithm: "other",
                canonicalDigest: String(repeating: "a", count: 64),
                lkgDigest: nil,
                lastValidatedRevision: DecimalUInt64(rawValue: 2),
                previousValidatedRevision: nil,
                validatedAt: Date(timeIntervalSince1970: 20)
            )
        ) { error in
            XCTAssertEqual(error as? IntegrityRecordValidationError, .invalidAlgorithm)
        }

        XCTAssertThrowsError(
            try IntegrityRecord(
                canonicalDigest: String(repeating: "A", count: 64),
                lkgDigest: nil,
                lastValidatedRevision: DecimalUInt64(rawValue: 2),
                previousValidatedRevision: nil,
                validatedAt: Date(timeIntervalSince1970: 20)
            )
        ) { error in
            XCTAssertEqual(error as? IntegrityRecordValidationError, .invalidDigest)
        }

        XCTAssertThrowsError(
            try IntegrityRecord(
                canonicalDigest: String(repeating: "a", count: 64),
                lkgDigest: nil,
                lastValidatedRevision: DecimalUInt64(rawValue: 2),
                previousValidatedRevision: DecimalUInt64(rawValue: 2),
                validatedAt: Date(timeIntervalSince1970: 20)
            )
        ) { error in
            XCTAssertEqual(error as? IntegrityRecordValidationError, .invalidRevision)
        }
    }
}
