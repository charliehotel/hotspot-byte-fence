import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class ProfileEnvelopePersistenceTests: XCTestCase {
    func testEnvelopeRequiresActiveProfilesForSelectionAndTransactions() throws {
        let profile = try makeProfile()
        let transaction = try makeTransaction(profileID: profile.profileID)
        let envelope = try StoreEnvelopeV1(
            storeRevision: DecimalUInt64(rawValue: 2),
            installationID: UUID(),
            hasCompletedProfile: true,
            observedArtifact: try makeArtifactObservation(),
            globalState: try makeGlobalState(),
            selectedProfileID: profile.profileID,
            languageOverride: .ko,
            profiles: [profile],
            preferenceTransactions: [transaction],
            eventLog: try EventLogRecord(),
            tombstoneDigest: String(repeating: "0", count: 64),
            integrity: try makeIntegrity()
        )

        XCTAssertEqual(try StoreJSONCodec.decode(
            StoreEnvelopeV1.self,
            from: StoreJSONCodec.encode(envelope)
        ), envelope)
        XCTAssertThrowsError(
            try StoreEnvelopeV1(
                storeRevision: DecimalUInt64(rawValue: 2),
                installationID: UUID(),
                hasCompletedProfile: true,
                observedArtifact: try makeArtifactObservation(),
                globalState: try makeGlobalState(),
                languageOverride: .ko,
                profiles: [],
                preferenceTransactions: [transaction],
                eventLog: try EventLogRecord(),
                tombstoneDigest: String(repeating: "0", count: 64),
                integrity: try makeIntegrity()
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .transactionProfileMissing)
        }
        XCTAssertThrowsError(
            try StoreEnvelopeV1(
                storeRevision: DecimalUInt64(rawValue: 2),
                installationID: UUID(),
                hasCompletedProfile: true,
                observedArtifact: try makeArtifactObservation(),
                globalState: try makeGlobalState(),
                selectedProfileID: UUID(),
                languageOverride: .ko,
                profiles: [profile],
                preferenceTransactions: [],
                eventLog: try EventLogRecord(),
                tombstoneDigest: String(repeating: "0", count: 64),
                integrity: try makeIntegrity()
            )
        ) { error in
            XCTAssertEqual(error as? StoreEnvelopeValidationError, .selectedProfileMissing)
        }
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

    private func makeProfile() throws -> ProfileRecord {
        try ProfileRecord(
            profileID: UUID(),
            aliasNFC: "SIM",
            ssidHex: nil,
            interfaceName: nil,
            confirmedBSSIDs: [],
            isComplete: false,
            sharesInterfaceSSID: false,
            limitBytes: ByteCount(10_000_000),
            resetDay: 1,
            cycle: try CycleRecord(
                trustedCycleDate: "2026-09-01",
                cycleStartInstant: Date(timeIntervalSince1970: 0),
                timeZoneID: "Asia/Seoul",
                lastTrustedWallClock: Date(timeIntervalSince1970: 10),
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

    private func makeTransaction(profileID: UUID) throws -> PreferenceTransactionRecord {
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
            transactionID: UUID(),
            profileID: profileID,
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: "en0", ssidHex: "0102"),
            originalArchive: original,
            intendedArchive: original.removingProfiles(matching: try SSID(hex: "0102")),
            preparedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeGlobalState() throws -> GlobalStateRecord {
        try GlobalStateRecord(
            safetyState: .normal,
            recoveryReason: nil,
            timeAdjustment: nil,
            counterCapability: .pending,
            identityCapability: .pending
        )
    }

    private func makeIntegrity() throws -> IntegrityRecord {
        try IntegrityRecord(
            canonicalDigest: String(repeating: "a", count: 64),
            lkgDigest: nil,
            lastValidatedRevision: DecimalUInt64(rawValue: 2),
            previousValidatedRevision: nil,
            validatedAt: Date(timeIntervalSince1970: 20)
        )
    }
}
