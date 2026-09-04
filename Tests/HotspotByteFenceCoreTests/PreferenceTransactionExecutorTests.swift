import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class PreferenceTransactionExecutorTests: XCTestCase {
    private let targetInterface = "en0"
    private let targetSSIDHex = "0102"
    private let otherSSIDHex = "0304"
    private let dummyBSSID = try! BSSID(string: "aa:bb:cc:dd:ee:ff")
    private let dummyDigest = String(repeating: "a", count: 64)
    private let initialInstant = Date(timeIntervalSince1970: 1000)

    func testExecuteGuardedDisassociateFailsWhenOperatorValidationFails() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let envelope = try makeEnvelope(profiles: [profile])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let digests = try makeDigests()

        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let targetSSID = try SSID(hex: targetSSIDHex)
        let targetSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: targetSSID,
            bssid: dummyBSSID
        )
        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .associated(targetSnapshot)
        )

        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: nil,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapter,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(
                error as? PreferenceTransactionExecutionError,
                .operatorValidationFailed(.missingContext)
            )
        }

        let unconfirmedContext = try makeContext(digests: digests, confirmed: false, date: initialInstant)
        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: unconfirmedContext,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapter,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(
                error as? PreferenceTransactionExecutionError,
                .operatorValidationFailed(.unconfirmed)
            )
        }

        let staleContext = try makeContext(digests: digests, confirmed: true, date: initialInstant.addingTimeInterval(-400))
        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: staleContext,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapter,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(
                error as? PreferenceTransactionExecutionError,
                .operatorValidationFailed(.staleContext)
            )
        }

        let mismatchedGateContext = try makeContext(digests: digests, confirmed: true, date: initialInstant, gateID: "F-07")
        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: mismatchedGateContext,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapter,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(
                error as? PreferenceTransactionExecutionError,
                .operatorValidationFailed(.gateOrCaseMismatch)
            )
        }
    }

    func testExecuteGuardedDisassociateFailsOnIdentityMismatch() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let envelope = try makeEnvelope(profiles: [profile])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let digests = try makeDigests()
        let context = try makeContext(digests: digests, confirmed: true, date: initialInstant)

        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let adapterNotAssociated = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .notAssociated(interfaceName: targetInterface, interfaceIndex: 1)
        )
        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: context,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapterNotAssociated,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .identityMismatch)
        }

        let otherSSID = try SSID(hex: otherSSIDHex)
        let otherSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: otherSSID,
            bssid: dummyBSSID
        )
        let adapterOtherSSID = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .associated(otherSnapshot)
        )
        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: context,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapterOtherSSID,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .identityMismatch)
        }

        let unlistedProfile = try makeProfile(profileID: UUID(), ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let targetSSID = try SSID(hex: targetSSIDHex)
        let targetSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: targetSSID,
            bssid: dummyBSSID
        )
        let adapterTarget = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .associated(targetSnapshot)
        )
        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: context,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: unlistedProfile,
                targetInterface: targetInterface,
                adapter: adapterTarget,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .identityMismatch)
        }
    }

    func testExecuteGuardedDisassociateHappyPathTargetAbsent() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let envelope = try makeEnvelope(profiles: [profile])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let digests = try makeDigests()
        let context = try makeContext(digests: digests, confirmed: true, date: initialInstant)

        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let targetSSID = try SSID(hex: targetSSIDHex)
        let targetSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: targetSSID,
            bssid: dummyBSSID
        )
        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .associated(targetSnapshot)
        )

        let result = try executor.executeGuardedDisassociate(
            context: context,
            candidateDigests: digests,
            gateID: "F-06",
            caseID: "CASE-01",
            targetProfile: profile,
            targetInterface: targetInterface,
            adapter: adapter,
            store: store,
            initialEnvelope: envelope,
            clock: clock
        )

        XCTAssertEqual(result.transaction.phase, .applied)
        XCTAssertEqual(result.disassociateOutcome, .targetAbsent)
        XCTAssertFalse(result.isRestored)
        XCTAssertEqual(adapter.commitCallCount, 1)
        XCTAssertEqual(adapter.disassociateCallCount, 1)

        let committedOps = store.committedOperations
        XCTAssertEqual(committedOps, [.preferencePrepare, .preferenceApplied])

        let finalEnvelope = try store.currentEnvelope
        XCTAssertEqual(finalEnvelope.preferenceTransactions.count, 1)
        let tx = finalEnvelope.preferenceTransactions[0]
        XCTAssertEqual(tx.phase, .applied)
        XCTAssertEqual(tx.profileID, profileID)
        XCTAssertEqual(tx.targetScope.interfaceName, targetInterface)
        XCTAssertEqual(tx.targetScope.ssidHex, targetSSIDHex)
    }

    func testExecuteGuardedDisassociateHappyPathUnrelatedNetworkConnected() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let envelope = try makeEnvelope(profiles: [profile])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let digests = try makeDigests()
        let context = try makeContext(digests: digests, confirmed: true, date: initialInstant)

        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let targetSSID = try SSID(hex: targetSSIDHex)
        let targetSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: targetSSID,
            bssid: dummyBSSID
        )
        let otherSSID = try SSID(hex: otherSSIDHex)
        let otherSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: otherSSID,
            bssid: dummyBSSID
        )

        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .associated(targetSnapshot)
        )
        adapter.observationSequence = [
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(otherSnapshot)
        ]

        let result = try executor.executeGuardedDisassociate(
            context: context,
            candidateDigests: digests,
            gateID: "F-06",
            caseID: "CASE-01",
            targetProfile: profile,
            targetInterface: targetInterface,
            adapter: adapter,
            store: store,
            initialEnvelope: envelope,
            clock: clock
        )

        XCTAssertEqual(result.disassociateOutcome, .unrelatedNetworkConnected)
        XCTAssertEqual(result.transaction.phase, .applied)
        XCTAssertEqual(adapter.disassociateCallCount, 1)
    }

    func testExecuteGuardedDisassociateReadBackMismatchMarksUnverified() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let envelope = try makeEnvelope(profiles: [profile])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let digests = try makeDigests()
        let context = try makeContext(digests: digests, confirmed: true, date: initialInstant)

        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let targetSSID = try SSID(hex: targetSSIDHex)
        let targetSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: targetSSID,
            bssid: dummyBSSID
        )

        final class MismatchOnReadAdapter: WiFiPreferenceAdapterProtocol, @unchecked Sendable {
            let original: CWConfigurationArchiveV1
            let snapshot: WiFiIdentitySnapshot
            init(original: CWConfigurationArchiveV1, snapshot: WiFiIdentitySnapshot) {
                self.original = original
                self.snapshot = snapshot
            }
            func readConfiguration(interfaceName: String) throws -> CWConfigurationArchiveV1 {
                original
            }
            func commitConfiguration(interfaceName: String, archive: CWConfigurationArchiveV1) throws {}
            func disassociate(interfaceName: String) throws {}
            func readCurrentIdentity(interfaceName: String) throws -> WiFiIdentityObservation {
                .associated(snapshot)
            }
        }

        let adapter = MismatchOnReadAdapter(original: originalArchive, snapshot: targetSnapshot)

        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: context,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapter,
                store: store,
                initialEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .readBackMismatch)
        }

        let committedOps = store.committedOperations
        XCTAssertEqual(committedOps, [.preferencePrepare, .preferenceApplied])
        let finalEnvelope = try store.currentEnvelope
        XCTAssertEqual(finalEnvelope.preferenceTransactions.count, 1)
        let tx = finalEnvelope.preferenceTransactions[0]
        XCTAssertEqual(tx.phase, .unverified)
        XCTAssertEqual(tx.lastError, .commitReadBackMismatch)
    }

    func testExecuteGuardedDisassociateVerificationFailedWhenTargetStillPresent() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let envelope = try makeEnvelope(profiles: [profile])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let digests = try makeDigests()
        let context = try makeContext(digests: digests, confirmed: true, date: initialInstant)

        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let targetSSID = try SSID(hex: targetSSIDHex)
        let targetSnapshot = WiFiIdentitySnapshot(
            interfaceName: targetInterface,
            interfaceIndex: 1,
            linkState: .associated,
            ssid: targetSSID,
            bssid: dummyBSSID
        )
        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: originalArchive,
            currentObservation: .associated(targetSnapshot)
        )
        adapter.observationSequence = [
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(targetSnapshot),
            .associated(targetSnapshot)
        ]

        XCTAssertThrowsError(
            try executor.executeGuardedDisassociate(
                context: context,
                candidateDigests: digests,
                gateID: "F-06",
                caseID: "CASE-01",
                targetProfile: profile,
                targetInterface: targetInterface,
                adapter: adapter,
                store: store,
                initialEnvelope: envelope,
                clock: clock,
                maxPostQueries: 3
            )
        ) { error in
            XCTAssertEqual(
                error as? PreferenceTransactionExecutionError,
                .disassociateVerificationFailed(.targetStillPresent)
            )
        }
    }

    func testRestoreTransactionHappyPath() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let intendedArchive = originalArchive.removingProfiles(matching: try SSID(hex: targetSSIDHex))
        let txID = UUID()
        let preparedTx = try PreferenceTransactionRecord.prepared(
            transactionID: txID,
            profileID: profileID,
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: targetInterface, ssidHex: targetSSIDHex),
            originalArchive: originalArchive,
            intendedArchive: intendedArchive,
            preparedAt: initialInstant
        )
        let appliedTx = try preparedTx.markApplied(
            lastWrittenArchive: intendedArchive,
            appliedAt: initialInstant.addingTimeInterval(5)
        )
        let envelope = try makeEnvelope(profiles: [profile], preferenceTransactions: [appliedTx])
        let clock = TxTestClock(date: initialInstant.addingTimeInterval(30), monotonic: 2000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)

        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: intendedArchive,
            currentObservation: .notAssociated(interfaceName: targetInterface, interfaceIndex: 1)
        )

        let restored = try executor.restoreTransaction(
            transactionID: txID,
            adapter: adapter,
            store: store,
            currentEnvelope: envelope,
            clock: clock
        )

        XCTAssertEqual(restored.phase, .restored)
        XCTAssertEqual(restored.observation, .verified)
        XCTAssertEqual(restored.observationSource, .eventBacked)
        XCTAssertEqual(adapter.commitCallCount, 1)
        XCTAssertEqual(try adapter.currentArchive.fingerprint(), try originalArchive.fingerprint())
        XCTAssertEqual(store.committedOperations, [.restoration])

        let finalEnvelope = try store.currentEnvelope
        XCTAssertEqual(finalEnvelope.preferenceTransactions[0].phase, .restored)
    }

    func testRestoreTransactionConflictWhenExternalChangeDetected() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let intendedArchive = originalArchive.removingProfiles(matching: try SSID(hex: targetSSIDHex))
        let txID = UUID()
        let preparedTx = try PreferenceTransactionRecord.prepared(
            transactionID: txID,
            profileID: profileID,
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: targetInterface, ssidHex: targetSSIDHex),
            originalArchive: originalArchive,
            intendedArchive: intendedArchive,
            preparedAt: initialInstant
        )
        let appliedTx = try preparedTx.markApplied(
            lastWrittenArchive: intendedArchive,
            appliedAt: initialInstant.addingTimeInterval(5)
        )
        let envelope = try makeEnvelope(profiles: [profile], preferenceTransactions: [appliedTx])
        let clock = TxTestClock(date: initialInstant.addingTimeInterval(30), monotonic: 2000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)

        let externalArchive = try makeArchive(ssidHex: otherSSIDHex)
        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: externalArchive,
            currentObservation: .notAssociated(interfaceName: targetInterface, interfaceIndex: 1)
        )

        XCTAssertThrowsError(
            try executor.restoreTransaction(
                transactionID: txID,
                adapter: adapter,
                store: store,
                currentEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(
                error as? PreferenceTransactionExecutionError,
                .restorationOwnershipConflict
            )
        }

        XCTAssertEqual(store.committedOperations, [.restoration])
        let finalEnvelope = try store.currentEnvelope
        XCTAssertEqual(finalEnvelope.preferenceTransactions[0].phase, .conflict)
        XCTAssertEqual(finalEnvelope.preferenceTransactions[0].lastError, .externalPreferenceChange)
    }

    func testRestoreTransactionReadBackMismatch() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let intendedArchive = originalArchive.removingProfiles(matching: try SSID(hex: targetSSIDHex))
        let txID = UUID()
        let preparedTx = try PreferenceTransactionRecord.prepared(
            transactionID: txID,
            profileID: profileID,
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: targetInterface, ssidHex: targetSSIDHex),
            originalArchive: originalArchive,
            intendedArchive: intendedArchive,
            preparedAt: initialInstant
        )
        let appliedTx = try preparedTx.markApplied(
            lastWrittenArchive: intendedArchive,
            appliedAt: initialInstant.addingTimeInterval(5)
        )
        let envelope = try makeEnvelope(profiles: [profile], preferenceTransactions: [appliedTx])
        let clock = TxTestClock(date: initialInstant.addingTimeInterval(30), monotonic: 2000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)

        final class ReadBackMismatchRestoreAdapter: WiFiPreferenceAdapterProtocol, @unchecked Sendable {
            var intended: CWConfigurationArchiveV1
            init(intended: CWConfigurationArchiveV1) {
                self.intended = intended
            }
            func readConfiguration(interfaceName: String) throws -> CWConfigurationArchiveV1 {
                intended
            }
            func commitConfiguration(interfaceName: String, archive: CWConfigurationArchiveV1) throws {}
            func disassociate(interfaceName: String) throws {}
            func readCurrentIdentity(interfaceName: String) throws -> WiFiIdentityObservation {
                .notAssociated(interfaceName: interfaceName, interfaceIndex: 1)
            }
        }

        let adapter = ReadBackMismatchRestoreAdapter(intended: intendedArchive)

        XCTAssertThrowsError(
            try executor.restoreTransaction(
                transactionID: txID,
                adapter: adapter,
                store: store,
                currentEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .readBackMismatch)
        }

        XCTAssertEqual(store.committedOperations, [.restoration])
        let finalEnvelope = try store.currentEnvelope
        XCTAssertEqual(finalEnvelope.preferenceTransactions[0].phase, .unverified)
        XCTAssertEqual(finalEnvelope.preferenceTransactions[0].lastError, .commitReadBackMismatch)
    }

    func testRestoreTransactionFailsForInvalidTransactionState() throws {
        let executor = PreferenceTransactionExecutor()
        let profileID = UUID()
        let profile = try makeProfile(profileID: profileID, ssidHex: targetSSIDHex, interfaceName: targetInterface)
        let originalArchive = try makeArchive(ssidHex: targetSSIDHex)
        let intendedArchive = originalArchive.removingProfiles(matching: try SSID(hex: targetSSIDHex))
        let txID = UUID()
        let preparedTx = try PreferenceTransactionRecord.prepared(
            transactionID: txID,
            profileID: profileID,
            targetScope: try InterfaceSSIDScopeRecord(interfaceName: targetInterface, ssidHex: targetSSIDHex),
            originalArchive: originalArchive,
            intendedArchive: intendedArchive,
            preparedAt: initialInstant
        )
        let envelope = try makeEnvelope(profiles: [profile], preferenceTransactions: [preparedTx])
        let clock = TxTestClock(date: initialInstant, monotonic: 1000)
        let store = TxTestEnvelopeStore(initialEnvelope: envelope)
        let adapter = MockWiFiPreferenceAdapter(
            currentArchive: intendedArchive,
            currentObservation: .notAssociated(interfaceName: targetInterface, interfaceIndex: 1)
        )

        XCTAssertThrowsError(
            try executor.restoreTransaction(
                transactionID: txID,
                adapter: adapter,
                store: store,
                currentEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .invalidTransactionState)
        }

        XCTAssertThrowsError(
            try executor.restoreTransaction(
                transactionID: UUID(),
                adapter: adapter,
                store: store,
                currentEnvelope: envelope,
                clock: clock
            )
        ) { error in
            XCTAssertEqual(error as? PreferenceTransactionExecutionError, .invalidTransactionState)
        }
    }

    private func makeDigests() throws -> CandidateDigestSetV1 {
        try CandidateDigestSetV1(
            unsignedAssetSHA256: dummyDigest,
            appBundleSHA256: dummyDigest,
            executableSHA256: dummyDigest,
            embeddedManifestSHA256: dummyDigest
        )
    }

    private func makeContext(
        digests: CandidateDigestSetV1,
        confirmed: Bool,
        date: Date,
        gateID: String = "F-06",
        caseID: String = "CASE-01"
    ) throws -> OperatorValidationContextV1 {
        let confirmation = try OperatorConfirmationRecordV1(
            confirmedAt: date,
            operatorConfirmed: confirmed,
            targetInterfaceName: targetInterface,
            targetSSIDHex: targetSSIDHex,
            targetBSSID: dummyBSSID.description,
            topologyRole: .t1,
            note: "test"
        )
        return try OperatorValidationContextV1(
            runID: UUID(),
            digests: digests,
            gateID: gateID,
            caseID: caseID,
            operatorConfirmation: confirmation
        )
    }

    private func makeArchive(ssidHex: String) throws -> CWConfigurationArchiveV1 {
        CWConfigurationArchiveV1(
            networkProfiles: [
                try CWNetworkProfileArchiveV1(
                    ssidHex: ssidHex,
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
    }

    private func makeProfile(
        profileID: UUID,
        ssidHex: String?,
        interfaceName: String?
    ) throws -> ProfileRecord {
        try ProfileRecord(
            profileID: profileID,
            aliasNFC: "Profile-(profileID.uuidString.prefix(4))",
            ssidHex: ssidHex,
            interfaceName: interfaceName,
            confirmedBSSIDs: [dummyBSSID],
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

    private func makeEnvelope(
        profiles: [ProfileRecord],
        preferenceTransactions: [PreferenceTransactionRecord] = []
    ) throws -> StoreEnvelopeV1 {
        let revision = DecimalUInt64(rawValue: 1)
        let interimIntegrity = try IntegrityRecord(
            algorithm: IntegrityRecord.algorithm,
            canonicalDigest: nil,
            lkgDigest: nil,
            lastValidatedRevision: revision,
            previousValidatedRevision: nil,
            validatedAt: initialInstant
        )
        let interim = try StoreEnvelopeV1(
            storeRevision: revision,
            previousGoodRevision: nil,
            installationID: UUID(),
            hasCompletedProfile: true,
            observedArtifact: try ArtifactObservationRecord(
                compiledModeObserved: .measurementOnly,
                buildManifestSHA256: dummyDigest,
                codeSignatureStatus: .unsigned,
                hardenedRuntimeStatus: .unavailable,
                notarizationStatus: .notApplicable,
                gatekeeperStatus: .notApplicable,
                quarantineStatus: .absent,
                macOSBuild: "24A335",
                observedAt: initialInstant
            ),
            globalState: try GlobalStateRecord(
                safetyState: .normal,
                recoveryReason: nil,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            ),
            selectedProfileID: profiles.first?.profileID,
            languageOverride: .ko,
            profiles: profiles,
            preferenceTransactions: preferenceTransactions,
            commandResults: [],
            notificationState: NotificationStateRecord(),
            eventLog: try EventLogRecord(),
            tombstoneDigest: String(repeating: "0", count: 64),
            integrity: interimIntegrity
        )
        return try interim.withSelfBoundDigest(validatedAt: initialInstant)
    }
}

private final class TxTestClock: ClockProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    private var monotonic: UInt64

    init(date: Date, monotonic: UInt64) {
        self.date = date
        self.monotonic = monotonic
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func monotonicNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return monotonic
    }
}

private final class TxTestEnvelopeStore: EnvelopeStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var committed: [(StoreEnvelopeV1, JournalOperation)] = []
    private var current: StoreEnvelopeV1

    init(initialEnvelope: StoreEnvelopeV1) {
        self.current = initialEnvelope
    }

    func commitEnvelope(_ document: StoreEnvelopeV1, operation: JournalOperation) throws {
        lock.lock()
        defer { lock.unlock() }
        committed.append((document, operation))
        current = document
    }

    func loadEnvelope() throws -> StoreLoadResult<StoreEnvelopeV1> {
        lock.lock()
        defer { lock.unlock() }
        return .loaded(current)
    }

    var committedOperations: [JournalOperation] {
        lock.lock()
        defer { lock.unlock() }
        return committed.map { $0.1 }
    }

    var currentEnvelope: StoreEnvelopeV1 {
        get throws {
            lock.lock()
            defer { lock.unlock() }
            return current
        }
    }
}
