import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class PreferenceTransactionTests: XCTestCase {
    func testPreparedTransactionStoresCanonicalArchivesAndScope() throws {
        let original = try archive(ssidHex: "0102", securityRawValue: 1)
        let intended = original.removingProfiles(matching: try SSID(hex: "0102"))
        let scope = try InterfaceSSIDScopeRecord(interfaceName: "en0", ssid: SSID(hex: "0102"))

        let record = try PreferenceTransactionRecord.prepared(
            transactionID: UUID(),
            profileID: UUID(),
            targetScope: scope,
            originalArchive: original,
            intendedArchive: intended,
            preparedAt: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(record.phase, .prepared)
        XCTAssertEqual(record.targetScope, scope)
        XCTAssertEqual(record.archiveSchemaVersion, 1)
        XCTAssertEqual(record.fingerprintAlgorithm, CWConfigurationArchiveV1.fingerprintAlgorithm)
        XCTAssertEqual(record.originalArchive, try original.canonicalBase64URL())
        XCTAssertEqual(record.originalFingerprint, try original.fingerprint())
        XCTAssertEqual(record.intendedArchive, try intended.canonicalBase64URL())
        XCTAssertEqual(record.intendedFingerprint, try intended.fingerprint())
        XCTAssertNil(record.lastWrittenArchive)
        XCTAssertNil(record.lastWrittenFingerprint)
        XCTAssertEqual(
            try StoreJSONCodec.decode(
                PreferenceTransactionRecord.self,
                from: StoreJSONCodec.encode(record)
            ),
            record
        )
    }

    func testAppliedTransactionRequiresIntendedLastWriteAndCanBecomeRestorationPending() throws {
        let original = try archive(ssidHex: "0102", securityRawValue: 1)
        let intended = original.removingProfiles(matching: try SSID(hex: "0102"))
        let prepared = try makePrepared(original: original, intended: intended)

        let applied = try prepared.markApplied(
            lastWrittenArchive: intended,
            appliedAt: Date(timeIntervalSince1970: 20)
        )
        let pending = try applied.markRestorationPending()

        XCTAssertEqual(applied.phase, .applied)
        XCTAssertEqual(applied.lastWrittenArchive, try intended.canonicalBase64URL())
        XCTAssertEqual(applied.lastWrittenFingerprint, try intended.fingerprint())
        XCTAssertEqual(applied.appliedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(pending.phase, .restorationPending)
        XCTAssertThrowsError(
            try prepared.markApplied(
                lastWrittenArchive: original,
                appliedAt: Date(timeIntervalSince1970: 20)
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionValidationError, .invalidFingerprint)
        }
    }

    func testRestoredTransactionSupportsNoOpAndPollBackedObservation() throws {
        let original = try archive(ssidHex: "0102", securityRawValue: 1)
        let intended = original.removingProfiles(matching: try SSID(hex: "0102"))
        let prepared = try makePrepared(original: original, intended: intended)

        let noOpRestored = try prepared.markRestored(
            at: Date(timeIntervalSince1970: 20),
            observation: .none,
            source: .none
        )
        let appliedRestored = try prepared
            .markApplied(lastWrittenArchive: intended, appliedAt: Date(timeIntervalSince1970: 20))
            .markRestorationPending()
            .markRestored(
                at: Date(timeIntervalSince1970: 30),
                observation: .verified,
                source: .pollBacked
            )

        XCTAssertEqual(noOpRestored.phase, .restored)
        XCTAssertEqual(noOpRestored.observation, .none)
        XCTAssertEqual(noOpRestored.observationSource, .none)
        XCTAssertNil(noOpRestored.lastWrittenArchive)
        XCTAssertEqual(appliedRestored.phase, .restored)
        XCTAssertEqual(appliedRestored.observation, .verified)
        XCTAssertEqual(appliedRestored.observationSource, .pollBacked)
        XCTAssertEqual(appliedRestored.restoredAt, Date(timeIntervalSince1970: 30))
    }

    func testConflictAndUnverifiedTransitionsExposeTypedReasons() throws {
        let original = try archive(ssidHex: "0102", securityRawValue: 1)
        let intended = original.removingProfiles(matching: try SSID(hex: "0102"))
        let prepared = try makePrepared(original: original, intended: intended)

        let conflict = try prepared.markConflict()
        let unverified = try prepared.markUnverified(error: .archiveDecodeFailure)

        XCTAssertEqual(conflict.phase, .conflict)
        XCTAssertEqual(conflict.lastError, .externalPreferenceChange)
        XCTAssertEqual(unverified.phase, .unverified)
        XCTAssertEqual(unverified.lastError, .archiveDecodeFailure)
    }

    func testDecodedTransactionRejectsMismatchedFingerprintAndState() throws {
        let original = try archive(ssidHex: "0102", securityRawValue: 1)
        let intended = original.removingProfiles(matching: try SSID(hex: "0102"))
        let prepared = try makePrepared(original: original, intended: intended)
        let encoded = try StoreJSONCodec.encode(prepared)
        let fingerprintTampered = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(
                of: prepared.originalFingerprint,
                with: String(repeating: "0", count: 64)
            )
        let phaseTampered = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "\"phase\":\"prepared\"", with: "\"phase\":\"applied\"")
        let restoredLifecycleOnly = try prepared.markRestored(
            at: Date(timeIntervalSince1970: 20),
            observation: .verified,
            source: .pollBacked
        )
        let lifecycleTampered = String(decoding: try StoreJSONCodec.encode(restoredLifecycleOnly), as: UTF8.self)
            .replacingOccurrences(of: "\"observationSource\":\"pollBacked\"", with: "\"observationSource\":\"lifecycleOnly\"")

        XCTAssertThrowsError(
            try StoreJSONCodec.decode(
                PreferenceTransactionRecord.self,
                from: Data(fingerprintTampered.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionValidationError, .invalidFingerprint)
        }
        XCTAssertThrowsError(
            try StoreJSONCodec.decode(
                PreferenceTransactionRecord.self,
                from: Data(phaseTampered.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionValidationError, .invalidState)
        }
        XCTAssertThrowsError(
            try StoreJSONCodec.decode(
                PreferenceTransactionRecord.self,
                from: Data(lifecycleTampered.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionValidationError, .invalidState)
        }
        XCTAssertThrowsError(try InterfaceSSIDScopeRecord(interfaceName: " ", ssidHex: "0102")) { error in
            XCTAssertEqual(error as? PreferenceTransactionValidationError, .invalidScope)
        }
    }

    private func makePrepared(
        original: CWConfigurationArchiveV1,
        intended: CWConfigurationArchiveV1
    ) throws -> PreferenceTransactionRecord {
        try PreferenceTransactionRecord.prepared(
            transactionID: UUID(),
            profileID: UUID(),
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: "en0", ssid: SSID(hex: "0102")),
            originalArchive: original,
            intendedArchive: intended,
            preparedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func archive(ssidHex: String, securityRawValue: UInt64) throws -> CWConfigurationArchiveV1 {
        CWConfigurationArchiveV1(
            networkProfiles: [
                try CWNetworkProfileArchiveV1(ssidHex: ssidHex, securityRawValue: DecimalUInt64(rawValue: securityRawValue))
            ],
            flags: CWConfigurationArchiveFlagsV1(
                requireAdministratorForAssociation: true,
                requireAdministratorForIBSSMode: false,
                requireAdministratorForPower: true,
                rememberJoinedNetworks: true
            )
        )
    }
}
