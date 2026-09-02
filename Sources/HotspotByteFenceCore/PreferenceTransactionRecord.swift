import Foundation

public struct PreferenceTransactionRecord: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let profileID: UUID
    public let targetScope: InterfaceSSIDScopeRecord
    public let phase: PreferenceTransactionPhaseV1
    public let observation: PreferenceObservationResultV1
    public let observationSource: PreferenceObservationSourceV1
    public let archiveSchemaVersion: UInt
    public let fingerprintAlgorithm: String
    public let originalArchive: String
    public let originalFingerprint: String
    public let intendedArchive: String
    public let intendedFingerprint: String
    public let lastWrittenArchive: String?
    public let lastWrittenFingerprint: String?
    public let preparedAt: Date
    public let appliedAt: Date?
    public let restoredAt: Date?
    public let lastError: PreferenceTransactionFailureV1?

    public static func prepared(
        transactionID: UUID,
        profileID: UUID,
        targetScope: InterfaceSSIDScopeRecord,
        originalArchive: CWConfigurationArchiveV1,
        intendedArchive: CWConfigurationArchiveV1,
        preparedAt: Date
    ) throws -> PreferenceTransactionRecord {
        try PreferenceTransactionRecord(
            transactionID: transactionID,
            profileID: profileID,
            targetScope: targetScope,
            archiveSchemaVersion: 1,
            fingerprintAlgorithm: CWConfigurationArchiveV1.fingerprintAlgorithm,
            originalArchive: try originalArchive.canonicalBase64URL(),
            originalFingerprint: try originalArchive.fingerprint(),
            intendedArchive: try intendedArchive.canonicalBase64URL(),
            intendedFingerprint: try intendedArchive.fingerprint(),
            preparedAt: preparedAt,
            state: PreferenceTransactionStateV1(
                phase: .prepared,
                observation: .none,
                observationSource: .none,
                lastWrittenArchive: nil,
                lastWrittenFingerprint: nil,
                appliedAt: nil,
                restoredAt: nil,
                lastError: nil
            )
        )
    }

    init(
        transactionID: UUID,
        profileID: UUID,
        targetScope: InterfaceSSIDScopeRecord,
        archiveSchemaVersion: UInt,
        fingerprintAlgorithm: String,
        originalArchive: String,
        originalFingerprint: String,
        intendedArchive: String,
        intendedFingerprint: String,
        preparedAt: Date,
        state: PreferenceTransactionStateV1
    ) throws {
        self.transactionID = transactionID
        self.profileID = profileID
        self.targetScope = targetScope
        self.phase = state.phase
        self.observation = state.observation
        self.observationSource = state.observationSource
        self.archiveSchemaVersion = archiveSchemaVersion
        self.fingerprintAlgorithm = fingerprintAlgorithm
        self.originalArchive = originalArchive
        self.originalFingerprint = originalFingerprint
        self.intendedArchive = intendedArchive
        self.intendedFingerprint = intendedFingerprint
        self.lastWrittenArchive = state.lastWrittenArchive
        self.lastWrittenFingerprint = state.lastWrittenFingerprint
        self.preparedAt = preparedAt
        self.appliedAt = state.appliedAt
        self.restoredAt = state.restoredAt
        self.lastError = state.lastError
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            transactionID: container.decode(UUID.self, forKey: .transactionID),
            profileID: container.decode(UUID.self, forKey: .profileID),
            targetScope: container.decode(InterfaceSSIDScopeRecord.self, forKey: .targetScope),
            archiveSchemaVersion: container.decode(UInt.self, forKey: .archiveSchemaVersion),
            fingerprintAlgorithm: container.decode(String.self, forKey: .fingerprintAlgorithm),
            originalArchive: container.decode(String.self, forKey: .originalArchive),
            originalFingerprint: container.decode(String.self, forKey: .originalFingerprint),
            intendedArchive: container.decode(String.self, forKey: .intendedArchive),
            intendedFingerprint: container.decode(String.self, forKey: .intendedFingerprint),
            preparedAt: container.decode(Date.self, forKey: .preparedAt),
            state: PreferenceTransactionStateV1(
                phase: container.decode(PreferenceTransactionPhaseV1.self, forKey: .phase),
                observation: container.decode(PreferenceObservationResultV1.self, forKey: .observation),
                observationSource: container.decode(
                    PreferenceObservationSourceV1.self,
                    forKey: .observationSource
                ),
                lastWrittenArchive: container.decodeIfPresent(String.self, forKey: .lastWrittenArchive),
                lastWrittenFingerprint: container.decodeIfPresent(
                    String.self,
                    forKey: .lastWrittenFingerprint
                ),
                appliedAt: container.decodeIfPresent(Date.self, forKey: .appliedAt),
                restoredAt: container.decodeIfPresent(Date.self, forKey: .restoredAt),
                lastError: container.decodeIfPresent(
                    PreferenceTransactionFailureV1.self,
                    forKey: .lastError
                )
            )
        )
    }

    func replacing(state: PreferenceTransactionStateV1) throws -> PreferenceTransactionRecord {
        try PreferenceTransactionRecord(
            transactionID: transactionID,
            profileID: profileID,
            targetScope: targetScope,
            archiveSchemaVersion: archiveSchemaVersion,
            fingerprintAlgorithm: fingerprintAlgorithm,
            originalArchive: originalArchive,
            originalFingerprint: originalFingerprint,
            intendedArchive: intendedArchive,
            intendedFingerprint: intendedFingerprint,
            preparedAt: preparedAt,
            state: state
        )
    }

    private func validate() throws {
        guard archiveSchemaVersion == 1 else {
            throw PreferenceTransactionValidationError.invalidArchiveSchema
        }
        guard fingerprintAlgorithm == CWConfigurationArchiveV1.fingerprintAlgorithm else {
            throw PreferenceTransactionValidationError.invalidFingerprintAlgorithm
        }

        let original = try decodeArchive(originalArchive)
        let intended = try decodeArchive(intendedArchive)
        guard PersistenceDigest.isValid(originalFingerprint),
              PersistenceDigest.isValid(intendedFingerprint),
              (try? original.fingerprint()) == originalFingerprint,
              (try? intended.fingerprint()) == intendedFingerprint else {
            throw PreferenceTransactionValidationError.invalidFingerprint
        }

        switch (lastWrittenArchive, lastWrittenFingerprint) {
        case (nil, nil):
            break
        case let (.some(encoded), .some(fingerprint)):
            let lastWritten = try decodeArchive(encoded)
            guard PersistenceDigest.isValid(fingerprint),
                  (try? lastWritten.fingerprint()) == fingerprint,
                  fingerprint == intendedFingerprint else {
                throw PreferenceTransactionValidationError.invalidFingerprint
            }
        default:
            throw PreferenceTransactionValidationError.invalidState
        }

        guard observationSourceMatchesResult() else {
            throw PreferenceTransactionValidationError.invalidState
        }
        if let appliedAt, appliedAt < preparedAt {
            throw PreferenceTransactionValidationError.invalidState
        }
        if let restoredAt, restoredAt < preparedAt {
            throw PreferenceTransactionValidationError.invalidState
        }
        if let appliedAt, let restoredAt, restoredAt < appliedAt {
            throw PreferenceTransactionValidationError.invalidState
        }

        switch phase {
        case .prepared:
            guard observation == .none,
                  observationSource == .none,
                  lastWrittenArchive == nil,
                  lastWrittenFingerprint == nil,
                  appliedAt == nil,
                  restoredAt == nil,
                  lastError == nil else {
                throw PreferenceTransactionValidationError.invalidState
            }
        case .applied, .restorationPending:
            guard lastWrittenArchive != nil,
                  lastWrittenFingerprint != nil,
                  appliedAt != nil,
                  lastError == nil else {
                throw PreferenceTransactionValidationError.invalidState
            }
        case .restored:
            guard restoredAt != nil, lastError == nil else {
                throw PreferenceTransactionValidationError.invalidState
            }
        case .conflict:
            guard lastError == .externalPreferenceChange else {
                throw PreferenceTransactionValidationError.invalidState
            }
        case .unverified:
            guard lastError != nil else {
                throw PreferenceTransactionValidationError.invalidState
            }
        }
    }

    private func decodeArchive(_ encoded: String) throws -> CWConfigurationArchiveV1 {
        do {
            return try CWConfigurationArchiveV1(base64URL: encoded)
        } catch {
            throw PreferenceTransactionValidationError.invalidArchive
        }
    }

    private func observationSourceMatchesResult() -> Bool {
        switch (observation, observationSource) {
        case (.none, .none),
             (.pending, .eventBacked), (.pending, .pollBacked), (.pending, .lifecycleOnly),
             (.verified, .eventBacked), (.verified, .pollBacked),
             (.unverified, .eventBacked), (.unverified, .pollBacked),
             (.unverified, .lifecycleOnly):
            true
        default:
            false
        }
    }

    enum CodingKeys: String, CodingKey {
        case transactionID
        case profileID
        case targetScope
        case phase
        case observation
        case observationSource
        case archiveSchemaVersion
        case fingerprintAlgorithm
        case originalArchive
        case originalFingerprint
        case intendedArchive
        case intendedFingerprint
        case lastWrittenArchive
        case lastWrittenFingerprint
        case preparedAt
        case appliedAt
        case restoredAt
        case lastError
    }
}
