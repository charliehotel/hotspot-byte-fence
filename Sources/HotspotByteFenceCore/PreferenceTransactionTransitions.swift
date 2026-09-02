import Foundation

public extension PreferenceTransactionRecord {
    func markApplied(
        lastWrittenArchive: CWConfigurationArchiveV1,
        appliedAt: Date
    ) throws -> PreferenceTransactionRecord {
        guard phase == .prepared else {
            throw PreferenceTransactionValidationError.invalidState
        }
        return try replacing(state: PreferenceTransactionStateV1(
            phase: .applied,
            observation: .none,
            observationSource: .none,
            lastWrittenArchive: try lastWrittenArchive.canonicalBase64URL(),
            lastWrittenFingerprint: try lastWrittenArchive.fingerprint(),
            appliedAt: appliedAt,
            restoredAt: nil,
            lastError: nil
        ))
    }

    func markRestorationPending() throws -> PreferenceTransactionRecord {
        guard phase == .applied else {
            throw PreferenceTransactionValidationError.invalidState
        }
        return try replacing(state: PreferenceTransactionStateV1(
            phase: .restorationPending,
            observation: observation,
            observationSource: observationSource,
            lastWrittenArchive: lastWrittenArchive,
            lastWrittenFingerprint: lastWrittenFingerprint,
            appliedAt: appliedAt,
            restoredAt: nil,
            lastError: nil
        ))
    }

    func markRestored(
        at restoredAt: Date,
        observation: PreferenceObservationResultV1,
        source: PreferenceObservationSourceV1
    ) throws -> PreferenceTransactionRecord {
        switch phase {
        case .prepared, .applied, .restorationPending:
            return try replacing(state: PreferenceTransactionStateV1(
                phase: .restored,
                observation: observation,
                observationSource: source,
                lastWrittenArchive: lastWrittenArchive,
                lastWrittenFingerprint: lastWrittenFingerprint,
                appliedAt: appliedAt,
                restoredAt: restoredAt,
                lastError: nil
            ))
        case .restored, .conflict, .unverified:
            throw PreferenceTransactionValidationError.invalidState
        }
    }

    func markConflict() throws -> PreferenceTransactionRecord {
        guard phase == .prepared || phase == .applied || phase == .restorationPending else {
            throw PreferenceTransactionValidationError.invalidState
        }
        return try replacing(state: PreferenceTransactionStateV1(
            phase: .conflict,
            observation: observation,
            observationSource: observationSource,
            lastWrittenArchive: lastWrittenArchive,
            lastWrittenFingerprint: lastWrittenFingerprint,
            appliedAt: appliedAt,
            restoredAt: nil,
            lastError: .externalPreferenceChange
        ))
    }

    func markUnverified(error: PreferenceTransactionFailureV1) throws -> PreferenceTransactionRecord {
        guard phase == .prepared || phase == .applied || phase == .restorationPending else {
            throw PreferenceTransactionValidationError.invalidState
        }
        return try replacing(state: PreferenceTransactionStateV1(
            phase: .unverified,
            observation: observation,
            observationSource: observationSource,
            lastWrittenArchive: lastWrittenArchive,
            lastWrittenFingerprint: lastWrittenFingerprint,
            appliedAt: appliedAt,
            restoredAt: nil,
            lastError: error
        ))
    }
}
