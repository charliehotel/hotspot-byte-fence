import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class StoreEnvelopeTests: XCTestCase {
    func testEnvelopeRoundTripsFoundationFieldsAndUsesExplicitNulls() throws {
        let transaction = try makeTransaction()
        let envelope = try makeEnvelope(preferenceTransactions: [transaction])

        let encoded = try StoreJSONCodec.encode(envelope)
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertEqual(try StoreJSONCodec.decode(StoreEnvelopeV1.self, from: encoded), envelope)
        XCTAssertTrue(json.contains("\"previousGoodRevision\":null"))
        XCTAssertTrue(json.contains("\"selectedProfileID\":null"))
        XCTAssertTrue(json.contains("\"lastError\":null"))
        XCTAssertTrue(json.contains("\"storeRevision\":\"2\""))
        XCTAssertTrue(json.contains("\"globalState\""))
        XCTAssertTrue(json.contains("\"integrity\""))
        XCTAssertTrue(json.contains("\"observedArtifact\""))
        XCTAssertTrue(json.contains("\"commandResults\""))
        XCTAssertTrue(json.contains("\"notificationState\""))
        XCTAssertTrue(json.contains("\"eventLog\""))
        XCTAssertEqual(envelope.storeRevision, DecimalUInt64(rawValue: 2))
        XCTAssertEqual(envelope.preferenceTransactions, [transaction])
        XCTAssertEqual(envelope.globalState.safetyState, .normal)
        XCTAssertEqual(envelope.integrity.lastValidatedRevision, envelope.storeRevision)
    }

    func testEnvelopeRejectsInvalidRevisionDigestAndDuplicateTransaction() throws {
        let transaction = try makeTransaction()
        let futureSchema = String(
            decoding: try StoreJSONCodec.encode(makeEnvelope(preferenceTransactions: [transaction])),
            as: UTF8.self
        ).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")

        XCTAssertThrowsError(
            try StoreJSONCodec.decode(
                StoreEnvelopeV1.self,
                from: Data(futureSchema.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .unsupportedSchemaVersion)
        }
        XCTAssertThrowsError(
            try makeEnvelope(
                previousGoodRevision: DecimalUInt64(rawValue: 2),
                preferenceTransactions: [transaction]
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .invalidRevision)
        }
        XCTAssertThrowsError(
            try makeEnvelope(
                preferenceTransactions: [transaction],
                tombstoneDigest: String(repeating: "A", count: 64)
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .invalidTombstoneDigest)
        }
        XCTAssertThrowsError(
            try makeEnvelope(preferenceTransactions: [transaction, transaction])
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .duplicateTransactionID)
        }
    }

    func testEnvelopePersistsTransactionsThroughJournalAndLKG() throws {
        let installationID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<StoreEnvelopeV1>(
            directory: directory,
            installationID: installationID
        )
        let transaction = try makeTransaction()
        let envelope = try makeEnvelope(
            installationID: installationID,
            preferenceTransactions: [transaction]
        )

        try store.commitEnvelope(envelope, operation: .preferencePrepare)

        XCTAssertEqual(try store.load(), .loaded(envelope))
        XCTAssertEqual(try store.decodeLKG(), envelope)
        XCTAssertEqual(
            try Data(contentsOf: store.paths.canonicalURL),
            try StoreJSONCodec.encode(envelope)
        )
        let journal = try XCTUnwrap(try store.readJournalIfPresent())
        XCTAssertEqual(journal.operation, .preferencePrepare)
        XCTAssertEqual(journal.targetStoreRevision, envelope.storeRevision)

        let mismatched = try makeEnvelope(
            installationID: UUID(),
            preferenceTransactions: [transaction]
        )
        XCTAssertThrowsError(try store.commitEnvelope(mismatched, operation: .preferenceApplied)) { error in
            XCTAssertEqual(error as? PersistenceError, .validationFailed)
        }
    }

    func testEnvelopeDecodeRejectsTamperedPreferenceTransaction() throws {
        let envelope = try makeEnvelope(preferenceTransactions: [try makeTransaction()])
        let encoded = try StoreJSONCodec.encode(envelope)
        let tampered = String(decoding: encoded, as: UTF8.self).replacingOccurrences(
            of: envelope.preferenceTransactions[0].originalFingerprint,
            with: String(repeating: "0", count: 64)
        )

        XCTAssertThrowsError(
            try StoreJSONCodec.decode(
                StoreEnvelopeV1.self,
                from: Data(tampered.utf8)
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .invalidTransaction)
        }
    }

    private func makeEnvelope(
        storeRevision: DecimalUInt64 = DecimalUInt64(rawValue: 2),
        previousGoodRevision: DecimalUInt64? = nil,
        installationID: UUID = UUID(),
        hasCompletedProfile: Bool = true,
        selectedProfileID: UUID? = nil,
        languageOverride: StoreLanguageOverrideV1 = .ko,
        preferenceTransactions: [PreferenceTransactionRecord] = [],
        commandResults: [CommandResultRecord] = [],
        notificationState: NotificationStateRecord = NotificationStateRecord(),
        eventLog: EventLogRecord? = nil,
        tombstoneDigest: String = String(repeating: "0", count: 64),
        globalState: GlobalStateRecord? = nil,
        integrity: IntegrityRecord? = nil
    ) throws -> StoreEnvelopeV1 {
        let profileIDs = preferenceTransactions.reduce(into: [UUID]()) { result, transaction in
            if !result.contains(transaction.profileID) {
                result.append(transaction.profileID)
            }
        }
        return try StoreEnvelopeV1(
            storeRevision: storeRevision,
            previousGoodRevision: previousGoodRevision,
            installationID: installationID,
            hasCompletedProfile: hasCompletedProfile,
            observedArtifact: try makeArtifactObservation(),
            globalState: try globalState ?? GlobalStateRecord(
                safetyState: .normal,
                recoveryReason: nil,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            ),
            selectedProfileID: selectedProfileID,
            languageOverride: languageOverride,
            profiles: try profileIDs.map(makeProfile),
            preferenceTransactions: preferenceTransactions,
            commandResults: commandResults,
            notificationState: notificationState,
            eventLog: try eventLog ?? EventLogRecord(),
            tombstoneDigest: tombstoneDigest,
            integrity: try integrity ?? IntegrityRecord(
                canonicalDigest: String(repeating: "a", count: 64),
                lkgDigest: nil,
                lastValidatedRevision: storeRevision,
                previousValidatedRevision: previousGoodRevision.flatMap {
                    $0.rawValue < storeRevision.rawValue ? $0 : nil
                },
                validatedAt: Date(timeIntervalSince1970: 20)
            )
        )
    }

    private func makeArtifactObservation() throws -> ArtifactObservationRecord {
        try ArtifactObservationRecord(
            compiledModeObserved: .measurementOnly,
            buildManifestSHA256: String(repeating: "0", count: 64),
            codeSignatureStatus: .unsigned,
            hardenedRuntimeStatus: .unavailable,
            notarizationStatus: .notApplicable,
            gatekeeperStatus: .notApplicable,
            quarantineStatus: .absent,
            macOSBuild: "24A335",
            observedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeProfile(profileID: UUID) throws -> ProfileRecord {
        try ProfileRecord(
            profileID: profileID,
            aliasNFC: "SIM",
            ssidHex: "0102",
            interfaceName: "en0",
            confirmedBSSIDs: [try BSSID(string: "aa:bb:cc:dd:ee:ff")],
            isComplete: true,
            sharesInterfaceSSID: false,
            limitBytes: ByteCount(10_000_000),
            resetDay: 1,
            cycle: try CycleRecord(
                trustedCycleDate: "2026-09-01",
                cycleStartInstant: Date(timeIntervalSince1970: 0),
                timeZoneID: "Asia/Seoul",
                lastTrustedWallClock: Date(timeIntervalSince1970: 15),
                timeAcknowledgementRequired: false
            ),
            measurement: try MeasurementRecord(
                usageBytes: ByteCount(0),
                baselinePending: true,
                lastTrustedIdentity: nil,
                lastRXBytes: nil,
                lastTXBytes: nil,
                lastSampleWallClock: nil,
                lastPersistedUsageAt: Date(timeIntervalSince1970: 10),
                bytesSinceLastFlush: ByteCount(0)
            ),
            protection: try ProtectionRecord(
                limitReached: false,
                pauseBlocking: false,
                blockingCapability: .measurementOnly,
                lastAuthorizationOutcome: .neverRequested,
                retry: try RetryRecord(
                    state: .none,
                    attemptIndex: 0,
                    nextEligibleAt: nil,
                    lastAttemptAt: nil
                ),
                lastSuppressionObservation: nil,
                lastFailureReason: nil,
                ownedTransactionID: nil
            ),
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeTransaction(
        transactionID: UUID = UUID()
    ) throws -> PreferenceTransactionRecord {
        let original = CWConfigurationArchiveV1(
            networkProfiles: [
                try CWNetworkProfileArchiveV1(
                    ssidHex: "0102",
                    securityRawValue: DecimalUInt64(rawValue: 1)
                )
            ],
            flags: CWConfigurationArchiveFlagsV1(
                requireAdministratorForAssociation: true,
                requireAdministratorForIBSSMode: false,
                requireAdministratorForPower: true,
                rememberJoinedNetworks: true
            )
        )
        return try PreferenceTransactionRecord.prepared(
            transactionID: transactionID,
            profileID: UUID(),
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: "en0", ssidHex: "0102"),
            originalArchive: original,
            intendedArchive: original.removingProfiles(matching: try SSID(hex: "0102")),
            preparedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hbf-envelope-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
