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

    func testStoreEnvelopeMakeInitial() throws {
        let installationID = UUID()
        let initial = try StoreEnvelopeV1.makeInitial(installationID: installationID)
        XCTAssertEqual(initial.installationID, installationID)
        XCTAssertEqual(initial.storeRevision, DecimalUInt64(rawValue: 1))
        XCTAssertNil(initial.previousGoodRevision)
        XCTAssertFalse(initial.hasCompletedProfile)
        XCTAssertTrue(initial.profiles.isEmpty)
        XCTAssertNoThrow(try initial.validateSelfBinding())
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
        ).withSelfBoundDigest()

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
        ).withSelfBoundDigest()
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

    func testEnvelopeSelfBoundDigestVerification() throws {
        let envelope = try makeEnvelope().withSelfBoundDigest()
        XCTAssertNoThrow(try envelope.validateSelfBinding())

        let encoded = try StoreJSONCodec.encode(envelope)
        let decoded = try StoreJSONCodec.decode(StoreEnvelopeV1.self, from: encoded)
        XCTAssertNoThrow(try decoded.validateSelfBinding())
        XCTAssertEqual(decoded, envelope)

        let tamperedIntegrity = try IntegrityRecord(
            canonicalDigest: String(repeating: "f", count: 64),
            lkgDigest: nil,
            lastValidatedRevision: envelope.storeRevision,
            previousValidatedRevision: envelope.previousGoodRevision,
            validatedAt: envelope.integrity.validatedAt
        )
        let tamperedEnvelope = try StoreEnvelopeV1(
            storeRevision: envelope.storeRevision,
            previousGoodRevision: envelope.previousGoodRevision,
            installationID: envelope.installationID,
            hasCompletedProfile: envelope.hasCompletedProfile,
            observedArtifact: envelope.observedArtifact,
            globalState: envelope.globalState,
            selectedProfileID: envelope.selectedProfileID,
            languageOverride: envelope.languageOverride,
            profiles: envelope.profiles,
            preferenceTransactions: envelope.preferenceTransactions,
            commandResults: envelope.commandResults,
            notificationState: envelope.notificationState,
            eventLog: envelope.eventLog,
            tombstoneDigest: envelope.tombstoneDigest,
            integrity: tamperedIntegrity
        )
        XCTAssertThrowsError(try tamperedEnvelope.validateSelfBinding()) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .integrityDigestMismatch)
        }
    }

    func testEnvelopeProfilePurgeRemovesScopedReferences() throws {
        let profile1ID = UUID()
        let profile2ID = UUID()
        let tx1ID = UUID()

        let profile1 = try makeProfile(profileID: profile1ID, alias: "Profile1", ownedTransactionID: tx1ID)
        let profile2 = try makeProfile(profileID: profile2ID, alias: "Profile2")

        let tx1 = try makeTransaction(transactionID: tx1ID, profileID: profile1ID)

        let notifState = NotificationStateRecord(
            profileNotificationStates: [
                profile1ID: try ProfileNotificationRecord(),
                profile2ID: try ProfileNotificationRecord()
            ],
            systemAuthorization: .authorized
        )

        let event1 = try EventRecord(
            sequence: DecimalUInt64(rawValue: 1),
            storeRevision: DecimalUInt64(rawValue: 2),
            occurredAt: Date(timeIntervalSince1970: 5),
            profileID: profile1ID,
            transactionID: tx1ID,
            kind: .preferencePrepared,
            details: EventDetailsV1(
                reason: .preferencePrepared,
                profileID: profile1ID,
                transactionID: tx1ID,
                fingerprint: tx1.originalFingerprint
            )
        )
        let event2 = try EventRecord(
            sequence: DecimalUInt64(rawValue: 2),
            storeRevision: DecimalUInt64(rawValue: 2),
            occurredAt: Date(timeIntervalSince1970: 6),
            profileID: profile2ID,
            kind: .profileChange,
            details: EventDetailsV1(
                reason: .profileChange,
                oldState: "initial",
                newState: "active",
                profileID: profile2ID
            )
        )
        let event3 = try EventRecord(
            sequence: DecimalUInt64(rawValue: 3),
            storeRevision: DecimalUInt64(rawValue: 2),
            occurredAt: Date(timeIntervalSince1970: 7),
            kind: .lifecycle,
            details: EventDetailsV1(
                reason: .normal,
                oldState: "launching",
                newState: "running",
                storeRevision: DecimalUInt64(rawValue: 2)
            )
        )
        let eventLog = try EventLogRecord(events: [event1, event2, event3])

        let baseEnvelope = try makeEnvelope(
            storeRevision: DecimalUInt64(rawValue: 2),
            selectedProfileID: profile1ID,
            profiles: [profile1, profile2],
            preferenceTransactions: [tx1],
            notificationState: notifState,
            eventLog: eventLog
        ).withSelfBoundDigest()

        let tombstoneDigest = String(repeating: "e", count: 64)
        let purged = try baseEnvelope.purgingProfile(
            id: profile1ID,
            newRevision: DecimalUInt64(rawValue: 3),
            deletedAt: Date(timeIntervalSince1970: 50),
            tombstoneDigest: tombstoneDigest
        )

        XCTAssertEqual(purged.profiles.count, 1)
        XCTAssertEqual(purged.profiles.first?.profileID, profile2ID)
        XCTAssertTrue(purged.preferenceTransactions.isEmpty)
        XCTAssertEqual(purged.notificationState.profileNotificationStates.count, 1)
        XCTAssertNil(purged.notificationState.profileNotificationStates[profile1ID])
        XCTAssertNotNil(purged.notificationState.profileNotificationStates[profile2ID])

       XCTAssertEqual(purged.eventLog.events.count, 3)
       XCTAssertFalse(purged.eventLog.events.contains(where: { $0.profileID == profile1ID }))
       XCTAssertFalse(purged.eventLog.events.contains(where: { $0.transactionID == tx1ID }))

        let deletionEvent: EventRecord = try XCTUnwrap(purged.eventLog.events.last)
        XCTAssertEqual(deletionEvent.kind, EventKindV1.profileDeletion)
        XCTAssertNil(deletionEvent.profileID)
        XCTAssertNil(deletionEvent.transactionID)
        XCTAssertEqual(deletionEvent.sequence, DecimalUInt64(rawValue: 4))
        XCTAssertEqual(deletionEvent.storeRevision, DecimalUInt64(rawValue: 3))
        XCTAssertEqual(deletionEvent.details.reason, EventReasonV1.profileDeleted)

        XCTAssertNil(purged.selectedProfileID)
        XCTAssertEqual(purged.storeRevision, DecimalUInt64(rawValue: 3))
        XCTAssertEqual(purged.previousGoodRevision, DecimalUInt64(rawValue: 2))
        XCTAssertEqual(purged.tombstoneDigest, tombstoneDigest)
        XCTAssertEqual(purged.integrity.lastValidatedRevision, DecimalUInt64(rawValue: 3))
        XCTAssertEqual(purged.integrity.previousValidatedRevision, DecimalUInt64(rawValue: 2))
        XCTAssertEqual(purged.integrity.lkgDigest, baseEnvelope.integrity.canonicalDigest)

        XCTAssertNoThrow(try purged.validateSelfBinding())

        XCTAssertThrowsError(
            try purged.purgingProfile(
                id: profile1ID,
                newRevision: DecimalUInt64(rawValue: 4),
                tombstoneDigest: tombstoneDigest
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .profileNotFound)
        }

        XCTAssertThrowsError(
            try purged.purgingProfile(
                id: profile2ID,
                newRevision: DecimalUInt64(rawValue: 3),
                tombstoneDigest: tombstoneDigest
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .invalidRevision)
        }

        XCTAssertThrowsError(
            try purged.purgingProfile(
                id: profile2ID,
                newRevision: DecimalUInt64(rawValue: 4),
                tombstoneDigest: "invalid-digest"
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .invalidTombstoneDigest)
        }
    }

    private func makeEnvelope(
        storeRevision: DecimalUInt64 = DecimalUInt64(rawValue: 2),
        previousGoodRevision: DecimalUInt64? = nil,
        installationID: UUID = UUID(),
        hasCompletedProfile: Bool = true,
        selectedProfileID: UUID? = nil,
        languageOverride: StoreLanguageOverrideV1 = .ko,
        profiles: [ProfileRecord]? = nil,
        preferenceTransactions: [PreferenceTransactionRecord] = [],
        commandResults: [CommandResultRecord] = [],
        notificationState: NotificationStateRecord = NotificationStateRecord(),
        eventLog: EventLogRecord? = nil,
        tombstoneDigest: String = String(repeating: "0", count: 64),
        globalState: GlobalStateRecord? = nil,
        integrity: IntegrityRecord? = nil
    ) throws -> StoreEnvelopeV1 {
        let defaultProfileIDs = preferenceTransactions.reduce(into: [UUID]()) { result, transaction in
            if !result.contains(transaction.profileID) {
                result.append(transaction.profileID)
            }
        }
        let resolvedProfiles = try profiles ?? defaultProfileIDs.enumerated().map { idx, id in
            try makeProfile(profileID: id, alias: "SIM(idx)")
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
            profiles: resolvedProfiles,
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

    private func makeProfile(
        profileID: UUID,
        alias: String = "SIM",
        ownedTransactionID: UUID? = nil
    ) throws -> ProfileRecord {
       try ProfileRecord(
           profileID: profileID,
            aliasNFC: alias,
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
        transactionID: UUID = UUID(),
        profileID: UUID = UUID()
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
            profileID: profileID,
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
