import Foundation

public struct PreferenceTransactionExecutionResult: Equatable, Sendable {
    public let transaction: PreferenceTransactionRecord
    public let disassociateOutcome: DisassociateOutcome
    public let isRestored: Bool

    public init(
        transaction: PreferenceTransactionRecord,
        disassociateOutcome: DisassociateOutcome,
        isRestored: Bool
    ) {
        self.transaction = transaction
        self.disassociateOutcome = disassociateOutcome
        self.isRestored = isRestored
    }
}

public final class PreferenceTransactionExecutor: Sendable {
    public init() {}

   public func executeGuardedDisassociate(
       context: OperatorValidationContextV1?,
       candidateDigests: CandidateDigestSetV1,
       gateID: String,
       caseID: String,
       targetProfile: ProfileRecord,
       targetInterface: String,
       adapter: WiFiPreferenceAdapterProtocol,
       store: EnvelopeStoreProtocol,
       initialEnvelope: StoreEnvelopeV1,
       clock: ClockProtocol = SystemClock(),
       maxPostQueries: Int = 5
   ) throws -> PreferenceTransactionExecutionResult {
       let now = clock.now()
       let validationResult = OperatorValidationContextValidator.validate(
           context: context,
           candidateDigests: candidateDigests,
           currentGateID: gateID,
           currentCaseID: caseID,
           now: now
       )
       guard validationResult == .valid else {
           throw PreferenceTransactionExecutionError.operatorValidationFailed(validationResult)
       }

       guard let targetSSIDHex = targetProfile.ssidHex,
             let targetSSID = try? SSID(hex: targetSSIDHex) else {
           throw PreferenceTransactionExecutionError.identityMismatch
       }

       if let profileInterface = targetProfile.interfaceName, profileInterface != targetInterface {
           throw PreferenceTransactionExecutionError.identityMismatch
       }

       guard initialEnvelope.profiles.contains(where: { $0.profileID == targetProfile.profileID }) else {
           throw PreferenceTransactionExecutionError.identityMismatch
       }

       let initialObservation = try adapter.readCurrentIdentity(interfaceName: targetInterface)
        guard case let .associated(snapshot) = initialObservation,
              snapshot.ssid.hex == targetSSID.hex,
              snapshot.interfaceName == targetInterface else {
            throw PreferenceTransactionExecutionError.identityMismatch
        }

        let originalArchive = try adapter.readConfiguration(interfaceName: targetInterface)
        let intendedArchive = originalArchive.removingProfiles(matching: targetSSID)

        let transactionID = UUID()
        let scope = try InterfaceSSIDScopeRecord(interfaceName: targetInterface, ssid: targetSSID)
        var transaction = try PreferenceTransactionRecord.prepared(
            transactionID: transactionID,
            profileID: targetProfile.profileID,
            targetScope: scope,
            originalArchive: originalArchive,
            intendedArchive: intendedArchive,
            preparedAt: now
        )

       var envelope = initialEnvelope
       var transactions = envelope.preferenceTransactions
       transactions.append(transaction)
       envelope = try envelope.updatingStore(now: now, preferenceTransactions: transactions)
       try store.commitEnvelope(envelope, operation: .preferencePrepare)

       let preCommitObservation = try adapter.readCurrentIdentity(interfaceName: targetInterface)
        guard case let .associated(preCommitSnapshot) = preCommitObservation,
              preCommitSnapshot.ssid.hex == targetSSID.hex else {
            throw PreferenceTransactionExecutionError.identityMismatch
        }

       try adapter.commitConfiguration(interfaceName: targetInterface, archive: intendedArchive)
       let readBack = try adapter.readConfiguration(interfaceName: targetInterface)
       guard try readBack.fingerprint() == intendedArchive.fingerprint() else {
           let unverifiedTx = try transaction.markUnverified(error: PreferenceTransactionFailureV1.commitReadBackMismatch)
           transactions = replaceTransaction(in: transactions, with: unverifiedTx)
           if let env = try? envelope.updatingStore(now: clock.now(), preferenceTransactions: transactions) {
               try? store.commitEnvelope(env, operation: .preferenceApplied)
           }
           throw PreferenceTransactionExecutionError.readBackMismatch
       }

       let appliedAt = clock.now()
       transaction = try transaction.markApplied(lastWrittenArchive: intendedArchive, appliedAt: appliedAt)
       transactions = replaceTransaction(in: transactions, with: transaction)
       envelope = try envelope.updatingStore(now: appliedAt, preferenceTransactions: transactions)
       try store.commitEnvelope(envelope, operation: .preferenceApplied)

       let preDisassociateObservation = try adapter.readCurrentIdentity(interfaceName: targetInterface)
        guard case let .associated(preDisassocSnapshot) = preDisassociateObservation,
              preDisassocSnapshot.ssid.hex == targetSSID.hex else {
            throw PreferenceTransactionExecutionError.identityMismatch
        }

        try adapter.disassociate(interfaceName: targetInterface)

        var disassociateOutcome: DisassociateOutcome = .targetStillPresent
        for _ in 0..<maxPostQueries {
            let obs = try adapter.readCurrentIdentity(interfaceName: targetInterface)
            switch obs {
            case .notAssociated:
                disassociateOutcome = .targetAbsent
                break
            case let .associated(currentSnap):
                if currentSnap.ssid.hex != targetSSID.hex {
                    disassociateOutcome = .unrelatedNetworkConnected
                    break
                }
            case .identityUnavailable:
                disassociateOutcome = .identityUnavailable
            }
            if disassociateOutcome == .targetAbsent || disassociateOutcome == .unrelatedNetworkConnected {
                break
            }
        }

        guard disassociateOutcome == .targetAbsent || disassociateOutcome == .unrelatedNetworkConnected else {
            throw PreferenceTransactionExecutionError.disassociateVerificationFailed(disassociateOutcome)
        }

        return PreferenceTransactionExecutionResult(
            transaction: transaction,
            disassociateOutcome: disassociateOutcome,
            isRestored: false
        )
    }

    public func restoreTransaction(
        transactionID: UUID,
        adapter: WiFiPreferenceAdapterProtocol,
        store: EnvelopeStoreProtocol,
        currentEnvelope: StoreEnvelopeV1,
        clock: ClockProtocol = SystemClock()
    ) throws -> PreferenceTransactionRecord {
        guard let transaction = currentEnvelope.preferenceTransactions.first(where: { $0.transactionID == transactionID }) else {
            throw PreferenceTransactionExecutionError.invalidTransactionState
        }
        guard transaction.phase == .applied || transaction.phase == .restorationPending else {
            throw PreferenceTransactionExecutionError.invalidTransactionState
        }

        let interfaceName = transaction.targetScope.interfaceName
        let currentConfig = try adapter.readConfiguration(interfaceName: interfaceName)
        let currentFingerprint = try currentConfig.fingerprint()

       guard currentFingerprint == transaction.lastWrittenFingerprint else {
           let conflictTx = try transaction.markConflict()
           let transactions = replaceTransaction(in: currentEnvelope.preferenceTransactions, with: conflictTx)
           let env = try currentEnvelope.updatingStore(now: clock.now(), preferenceTransactions: transactions)
           try store.commitEnvelope(env, operation: .restoration)
           throw PreferenceTransactionExecutionError.restorationOwnershipConflict
       }

       let originalArchive = try CWConfigurationArchiveV1(base64URL: transaction.originalArchive)
       try adapter.commitConfiguration(interfaceName: interfaceName, archive: originalArchive)

       let readBack = try adapter.readConfiguration(interfaceName: interfaceName)
       guard try readBack.fingerprint() == transaction.originalFingerprint else {
           let unverifiedTx = try transaction.markUnverified(error: PreferenceTransactionFailureV1.commitReadBackMismatch)
           let transactions = replaceTransaction(in: currentEnvelope.preferenceTransactions, with: unverifiedTx)
           let env = try currentEnvelope.updatingStore(now: clock.now(), preferenceTransactions: transactions)
           try store.commitEnvelope(env, operation: .restoration)
           throw PreferenceTransactionExecutionError.readBackMismatch
       }

       let restoredAt = clock.now()
       let restoredTx = try transaction.markRestored(
           at: restoredAt,
           observation: .verified,
           source: .eventBacked
       )
       let transactions = replaceTransaction(in: currentEnvelope.preferenceTransactions, with: restoredTx)
       let env = try currentEnvelope.updatingStore(now: restoredAt, preferenceTransactions: transactions)
       try store.commitEnvelope(env, operation: .restoration)
       return restoredTx
   }

   private func replaceTransaction(
        in list: [PreferenceTransactionRecord],
        with updated: PreferenceTransactionRecord
    ) -> [PreferenceTransactionRecord] {
        list.map { $0.transactionID == updated.transactionID ? updated : $0 }
    }
}
