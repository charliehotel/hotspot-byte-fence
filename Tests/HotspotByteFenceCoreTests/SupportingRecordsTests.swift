import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class SupportingRecordsTests: XCTestCase {
    func testArtifactObservationRoundTripAndValidation() throws {
        let record = try ArtifactObservationRecord(
            compiledModeObserved: .measurementOnly,
            buildManifestSHA256: String(repeating: "a", count: 64),
            codeSignatureStatus: .unsigned,
            hardenedRuntimeStatus: .unavailable,
            notarizationStatus: .notApplicable,
            gatekeeperStatus: .notApplicable,
            quarantineStatus: .absent,
            macOSBuild: "24A335",
            observedAt: Date(timeIntervalSince1970: 100)
        )
        let encoded = try StoreJSONCodec.encode(record)
        let decoded = try StoreJSONCodec.decode(ArtifactObservationRecord.self, from: encoded)
        XCTAssertEqual(decoded, record)

        XCTAssertThrowsError(
            try ArtifactObservationRecord(
                compiledModeObserved: .measurementOnly,
                buildManifestSHA256: String(repeating: "a", count: 64),
                releaseManifestID: "rel-1",
                codeSignatureStatus: .unsigned,
                hardenedRuntimeStatus: .unavailable,
                notarizationStatus: .notApplicable,
                gatekeeperStatus: .notApplicable,
                quarantineStatus: .absent,
                macOSBuild: "24A335",
                observedAt: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(error as? ArtifactObservationRecordValidationError, .invalidReleaseManifestBinding)
        }
    }

    func testCommandResultRecordRoundTripAndValidation() throws {
        let command = try CommandResultRecord(
            commandName: .selectProfile,
            idempotencyKey: UUID(),
            outcome: .succeeded,
            resultCode: .success,
            storeRevision: DecimalUInt64(rawValue: 5),
            resultDigest: String(repeating: "b", count: 64),
            recordedAt: Date(timeIntervalSince1970: 200)
        )
        let encoded = try StoreJSONCodec.encode(command)
        let decoded = try StoreJSONCodec.decode(CommandResultRecord.self, from: encoded)
        XCTAssertEqual(decoded, command)

        XCTAssertThrowsError(
            try CommandResultRecord(
                commandName: .selectProfile,
                idempotencyKey: UUID(),
                outcome: .succeeded,
                resultCode: .success,
                storeRevision: DecimalUInt64(rawValue: 5),
                resultDigest: "invalid_digest",
                recordedAt: Date(timeIntervalSince1970: 200)
            )
        ) { error in
            XCTAssertEqual(error as? CommandResultRecordValidationError, .invalidDigest)
        }
    }

    func testNotificationRecordsRoundTripAndValidation() throws {
        let profileID = UUID()
        let profileRecord = try ProfileNotificationRecord(
            successNotifiedCycleDate: "2026-09-01",
            failureMute: .untilCycleEnds,
            muteExpiresAt: nil,
            muteCycleDate: "2026-09-01",
            lastFailureNotificationAt: Date(timeIntervalSince1970: 50)
        )
        let notifState = NotificationStateRecord(
            profileNotificationStates: [profileID: profileRecord],
            systemAuthorization: .authorized
        )
        let encoded = try StoreJSONCodec.encode(notifState)
        let decoded = try StoreJSONCodec.decode(NotificationStateRecord.self, from: encoded)
        XCTAssertEqual(decoded, notifState)

        XCTAssertThrowsError(
            try ProfileNotificationRecord(
                failureMute: .untilInstant,
                muteExpiresAt: nil
            )
        ) { error in
            XCTAssertEqual(error as? ProfileNotificationRecordValidationError, .invalidMuteState)
        }
    }

    func testEventLogRecordRoundTripAndValidation() throws {
        let profileID = UUID()
        let details = EventDetailsV1(
            reason: .counterSample,
            profileID: profileID,
            bytes: DecimalUInt64(rawValue: 1024)
        )
        let event = try EventRecord(
            sequence: DecimalUInt64(rawValue: 1),
            storeRevision: DecimalUInt64(rawValue: 2),
            occurredAt: Date(timeIntervalSince1970: 10),
            profileID: profileID,
            kind: .counterSample,
            redactionClass: .public,
            details: details
        )
        let log = try EventLogRecord(events: [event])
        let encoded = try StoreJSONCodec.encode(log)
        let decoded = try StoreJSONCodec.decode(EventLogRecord.self, from: encoded)
        XCTAssertEqual(decoded, log)

        let badDetails = EventDetailsV1(
            reason: .counterSample,
            attemptIndex: 3
        )
        XCTAssertThrowsError(
            try EventRecord(
                sequence: DecimalUInt64(rawValue: 2),
                storeRevision: DecimalUInt64(rawValue: 2),
                occurredAt: Date(timeIntervalSince1970: 10),
                kind: .counterSample,
                details: badDetails
            )
        ) { error in
            guard case .disallowedDetailsField(let field, let kind) = error as? EventValidationError else {
                XCTFail("Expected disallowedDetailsField, got \(error)"); return
            }
            XCTAssertEqual(field, "attemptIndex")
            XCTAssertEqual(kind, .counterSample)
        }

        XCTAssertThrowsError(
            try EventRecord(
                sequence: DecimalUInt64(rawValue: 2),
                storeRevision: DecimalUInt64(rawValue: 2),
                occurredAt: Date(timeIntervalSince1970: 10),
                kind: .launch,
                redactionClass: .secretProhibited,
                details: EventDetailsV1(reason: .launch, storeRevision: DecimalUInt64(rawValue: 2))
            )
        ) { error in
            XCTAssertEqual(error as? EventValidationError, .secretProhibitedPersisted)
        }
    }

    func testCrossRecordInvariantsInStoreEnvelope() throws {
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID)
        let missingID = UUID()

        let badNotifState = NotificationStateRecord(
            profileNotificationStates: [missingID: try ProfileNotificationRecord()],
            systemAuthorization: .authorized
        )
        XCTAssertThrowsError(
            try makeEnvelope(profiles: [profile], notificationState: badNotifState)
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .notificationProfileMissing)
        }

        let cmdKey = UUID()
        let cmd1 = try CommandResultRecord(
            commandName: .selectProfile,
            idempotencyKey: cmdKey,
            outcome: .succeeded,
            resultCode: .success,
            storeRevision: DecimalUInt64(rawValue: 2),
            resultDigest: String(repeating: "0", count: 64),
            recordedAt: Date(timeIntervalSince1970: 10)
        )
        let cmd2 = try CommandResultRecord(
            commandName: .selectProfile,
            idempotencyKey: cmdKey,
            outcome: .failed,
            resultCode: .conflict,
            storeRevision: DecimalUInt64(rawValue: 2),
            resultDigest: String(repeating: "0", count: 64),
            recordedAt: Date(timeIntervalSince1970: 11)
        )
        XCTAssertThrowsError(
            try makeEnvelope(profiles: [profile], commandResults: [cmd1, cmd2])
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .duplicateCommandIdempotencyKey)
        }

        let event = try EventRecord(
            sequence: DecimalUInt64(rawValue: 1),
            storeRevision: DecimalUInt64(rawValue: 2),
            occurredAt: Date(timeIntervalSince1970: 10),
            profileID: missingID,
            kind: .counterSample,
            details: EventDetailsV1(reason: .counterSample, profileID: missingID)
        )
        XCTAssertThrowsError(
            try makeEnvelope(profiles: [profile], eventLog: EventLogRecord(events: [event]))
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .eventProfileMissing)
        }
    }

    private func makeEnvelope(
        profiles: [ProfileRecord],
        commandResults: [CommandResultRecord] = [],
        notificationState: NotificationStateRecord = NotificationStateRecord(),
        eventLog: EventLogRecord? = nil
    ) throws -> StoreEnvelopeV1 {
        try StoreEnvelopeV1(
            storeRevision: DecimalUInt64(rawValue: 2),
            installationID: UUID(),
            hasCompletedProfile: true,
            observedArtifact: ArtifactObservationRecord(
                compiledModeObserved: .measurementOnly,
                buildManifestSHA256: String(repeating: "0", count: 64),
                codeSignatureStatus: .unsigned,
                hardenedRuntimeStatus: .unavailable,
                notarizationStatus: .notApplicable,
                gatekeeperStatus: .notApplicable,
                quarantineStatus: .absent,
                macOSBuild: "24A335",
                observedAt: Date(timeIntervalSince1970: 10)
            ),
            globalState: GlobalStateRecord(
                safetyState: .normal,
                recoveryReason: nil,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            ),
            selectedProfileID: profiles.first?.profileID,
            languageOverride: .ko,
            profiles: profiles,
            preferenceTransactions: [],
            commandResults: commandResults,
            notificationState: notificationState,
            eventLog: try eventLog ?? EventLogRecord(),
            tombstoneDigest: String(repeating: "0", count: 64),
            integrity: IntegrityRecord(
                canonicalDigest: String(repeating: "a", count: 64),
                lkgDigest: nil,
                lastValidatedRevision: DecimalUInt64(rawValue: 2),
                previousValidatedRevision: nil,
                validatedAt: Date(timeIntervalSince1970: 20)
            )
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
}
