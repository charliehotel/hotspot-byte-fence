import Foundation

public enum GlobalRecoveryReasonV1: String, Codable, Equatable, Sendable {
    case corruptStore
    case unknownSchema
    case migrationFailure
    case writeFailure
    case flushFailure
    case arithmeticOverflow
    case counterCapabilityFailure
    case integrityFailure
    case permissionModeFailure
    case archiveDecodeFailure
    case deletionRecovery
    case releaseManifestMismatch
}

public enum TimeAdjustmentReasonV1: String, Codable, Equatable, Sendable {
    case earlierCycle
    case backwardWallClock
    case wallMonotonicDivergence
}

public enum GlobalStateRecordValidationError: Error, Equatable, Sendable {
    case invalidRecoveryReason
    case invalidTimeAdjustment
    case missingNullableField
}

public struct TimeAdjustmentRecord: Codable, Equatable, Sendable {
    public let reason: TimeAdjustmentReasonV1
    public let trustedCycleDate: String
    public let observedCycleDate: String
    public let timeZoneID: String
    public let observedAt: Date
    public let acknowledgementRequired: Bool

    public init(
        reason: TimeAdjustmentReasonV1,
        trustedCycleDate: String,
        observedCycleDate: String,
        timeZoneID: String,
        observedAt: Date,
        acknowledgementRequired: Bool
    ) throws {
        guard PersistenceDateValidation.isCanonicalDate(trustedCycleDate),
              PersistenceDateValidation.isCanonicalDate(observedCycleDate),
              TimeZone(identifier: timeZoneID) != nil,
              observedAt.timeIntervalSince1970.isFinite else {
            throw GlobalStateRecordValidationError.invalidTimeAdjustment
        }
        self.reason = reason
        self.trustedCycleDate = trustedCycleDate
        self.observedCycleDate = observedCycleDate
        self.timeZoneID = timeZoneID
        self.observedAt = observedAt
        self.acknowledgementRequired = acknowledgementRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            reason: container.decode(TimeAdjustmentReasonV1.self, forKey: .reason),
            trustedCycleDate: container.decode(String.self, forKey: .trustedCycleDate),
            observedCycleDate: container.decode(String.self, forKey: .observedCycleDate),
            timeZoneID: container.decode(String.self, forKey: .timeZoneID),
            observedAt: container.decode(Date.self, forKey: .observedAt),
            acknowledgementRequired: container.decode(
                Bool.self,
                forKey: .acknowledgementRequired
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case reason
        case trustedCycleDate
        case observedCycleDate
        case timeZoneID
        case observedAt
        case acknowledgementRequired
    }
}

public struct GlobalStateRecord: Codable, Equatable, Sendable {
    public let safetyState: GlobalSafetyState
    public let recoveryReason: GlobalRecoveryReasonV1?
    public let timeAdjustment: TimeAdjustmentRecord?
    public let counterCapability: CounterCapabilityStatus
    public let identityCapability: IdentityCapabilityStatus

    public init(
        safetyState: GlobalSafetyState,
        recoveryReason: GlobalRecoveryReasonV1?,
        timeAdjustment: TimeAdjustmentRecord?,
        counterCapability: CounterCapabilityStatus,
        identityCapability: IdentityCapabilityStatus
    ) throws {
        self.safetyState = safetyState
        self.recoveryReason = recoveryReason
        self.timeAdjustment = timeAdjustment
        self.counterCapability = counterCapability
        self.identityCapability = identityCapability
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.recoveryReason), container.contains(.timeAdjustment) else {
            throw GlobalStateRecordValidationError.missingNullableField
        }
        try self.init(
            safetyState: container.decode(GlobalSafetyState.self, forKey: .safetyState),
            recoveryReason: container.decodeIfPresent(
                GlobalRecoveryReasonV1.self,
                forKey: .recoveryReason
            ),
            timeAdjustment: container.decodeIfPresent(
                TimeAdjustmentRecord.self,
                forKey: .timeAdjustment
            ),
            counterCapability: container.decode(
                CounterCapabilityStatus.self,
                forKey: .counterCapability
            ),
            identityCapability: container.decode(
                IdentityCapabilityStatus.self,
                forKey: .identityCapability
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(safetyState, forKey: .safetyState)
        try encodeExplicitOptional(recoveryReason, in: &container, forKey: .recoveryReason)
        try encodeExplicitOptional(timeAdjustment, in: &container, forKey: .timeAdjustment)
        try container.encode(counterCapability, forKey: .counterCapability)
        try container.encode(identityCapability, forKey: .identityCapability)
    }

    private func validate() throws {
        switch safetyState {
        case .normal, .multipleProfilesConnected:
            guard recoveryReason == nil, timeAdjustment == nil else {
                throw GlobalStateRecordValidationError.invalidRecoveryReason
            }
        case .recoveryRequired:
            guard recoveryReason != nil, timeAdjustment == nil else {
                throw GlobalStateRecordValidationError.invalidRecoveryReason
            }
        case .timeAdjustmentRequired:
            guard recoveryReason == nil,
                  let timeAdjustment,
                  timeAdjustment.acknowledgementRequired else {
                throw GlobalStateRecordValidationError.invalidTimeAdjustment
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case safetyState
        case recoveryReason
        case timeAdjustment
        case counterCapability
        case identityCapability
    }
}

public enum IntegrityRecordValidationError: Error, Equatable, Sendable {
    case invalidAlgorithm
    case invalidDigest
    case invalidRevision
    case invalidDate
    case missingNullableField
}

public struct IntegrityRecord: Codable, Equatable, Sendable {
    public static let algorithm = "hbf-store-v1-sha256"

    public let algorithm: String
    public let canonicalDigest: String?
    public let lkgDigest: String?
    public let lastValidatedRevision: DecimalUInt64
    public let previousValidatedRevision: DecimalUInt64?
    public let validatedAt: Date

    public init(
        algorithm: String = IntegrityRecord.algorithm,
        canonicalDigest: String? = nil,
        lkgDigest: String?,
        lastValidatedRevision: DecimalUInt64,
        previousValidatedRevision: DecimalUInt64?,
        validatedAt: Date
    ) throws {
        self.algorithm = algorithm
        self.canonicalDigest = canonicalDigest
        self.lkgDigest = lkgDigest
        self.lastValidatedRevision = lastValidatedRevision
        self.previousValidatedRevision = previousValidatedRevision
        self.validatedAt = validatedAt
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.canonicalDigest),
              container.contains(.lkgDigest),
              container.contains(.previousValidatedRevision) else {
            throw IntegrityRecordValidationError.missingNullableField
        }
        guard let canonicalDigest = try container.decodeIfPresent(String.self, forKey: .canonicalDigest) else {
            throw IntegrityRecordValidationError.invalidDigest
        }
        try self.init(
            algorithm: container.decode(String.self, forKey: .algorithm),
            canonicalDigest: canonicalDigest,
            lkgDigest: container.decodeIfPresent(String.self, forKey: .lkgDigest),
            lastValidatedRevision: container.decode(
                DecimalUInt64.self,
                forKey: .lastValidatedRevision
            ),
            previousValidatedRevision: container.decodeIfPresent(
                DecimalUInt64.self,
                forKey: .previousValidatedRevision
            ),
            validatedAt: container.decode(Date.self, forKey: .validatedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(algorithm, forKey: .algorithm)
        try encodeExplicitOptional(canonicalDigest, in: &container, forKey: .canonicalDigest)
        try encodeExplicitOptional(lkgDigest, in: &container, forKey: .lkgDigest)
        try container.encode(lastValidatedRevision, forKey: .lastValidatedRevision)
        try encodeExplicitOptional(
            previousValidatedRevision,
            in: &container,
            forKey: .previousValidatedRevision
        )
        try container.encode(validatedAt, forKey: .validatedAt)
    }

    private func validate() throws {
        guard algorithm == Self.algorithm else {
            throw IntegrityRecordValidationError.invalidAlgorithm
        }
        if let canonicalDigest {
            guard PersistenceDigest.isValid(canonicalDigest) else {
                throw IntegrityRecordValidationError.invalidDigest
            }
        }
        guard lkgDigest.map(PersistenceDigest.isValid) ?? true else {
            throw IntegrityRecordValidationError.invalidDigest
        }
        if let previousValidatedRevision,
           previousValidatedRevision.rawValue >= lastValidatedRevision.rawValue {
            throw IntegrityRecordValidationError.invalidRevision
        }
        guard validatedAt.timeIntervalSince1970.isFinite else {
            throw IntegrityRecordValidationError.invalidDate
        }
    }

    public func unhashed() throws -> IntegrityRecord {
        try IntegrityRecord(
            algorithm: algorithm,
            canonicalDigest: nil,
            lkgDigest: nil,
            lastValidatedRevision: lastValidatedRevision,
            previousValidatedRevision: previousValidatedRevision,
            validatedAt: validatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case canonicalDigest
        case lkgDigest
        case lastValidatedRevision
        case previousValidatedRevision
        case validatedAt
    }
}
