import Foundation

public enum RetryStateV1: String, Codable, Equatable, Sendable {
    case none
    case scheduled
    case running
    case stopped
}

public struct RetryRecord: Codable, Equatable, Sendable {
    public let state: RetryStateV1
    public let attemptIndex: UInt
    public let nextEligibleAt: Date?
    public let lastAttemptAt: Date?

    public init(
        state: RetryStateV1,
        attemptIndex: UInt,
        nextEligibleAt: Date?,
        lastAttemptAt: Date?
    ) throws {
        if state == .none,
           attemptIndex != 0 || nextEligibleAt != nil || lastAttemptAt != nil {
            throw ProfileRecordValidationError.invalidRetryState
        }
        self.state = state
        self.attemptIndex = attemptIndex
        self.nextEligibleAt = nextEligibleAt
        self.lastAttemptAt = lastAttemptAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.nextEligibleAt), container.contains(.lastAttemptAt) else {
            throw ProfileRecordValidationError.invalidRetryState
        }
        try self.init(
            state: container.decode(RetryStateV1.self, forKey: .state),
            attemptIndex: container.decode(UInt.self, forKey: .attemptIndex),
            nextEligibleAt: container.decodeIfPresent(Date.self, forKey: .nextEligibleAt),
            lastAttemptAt: container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(attemptIndex, forKey: .attemptIndex)
        try encodeExplicitOptional(nextEligibleAt, in: &container, forKey: .nextEligibleAt)
        try encodeExplicitOptional(lastAttemptAt, in: &container, forKey: .lastAttemptAt)
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case attemptIndex
        case nextEligibleAt
        case lastAttemptAt
    }
}

public struct ObservationSummaryRecord: Codable, Equatable, Sendable {
    public let result: PreferenceObservationResultV1
    public let source: PreferenceObservationSourceV1
    public let awakeSecondsObserved: UInt
    public let maxGapSeconds: UInt
    public let targetAbsentAtEnd: Bool

    public init(
        result: PreferenceObservationResultV1,
        source: PreferenceObservationSourceV1,
        awakeSecondsObserved: UInt,
        maxGapSeconds: UInt,
        targetAbsentAtEnd: Bool
    ) throws {
        let valid = switch (result, source) {
        case (.none, .none):
            awakeSecondsObserved == 0 && maxGapSeconds == 0
        case (.pending, .eventBacked), (.pending, .pollBacked):
            true
        case (.verified, .eventBacked):
            awakeSecondsObserved >= 30 && maxGapSeconds <= 2 && targetAbsentAtEnd
        case (.unverified, .eventBacked), (.unverified, .pollBacked), (.unverified, .lifecycleOnly):
            true
        default:
            false
        }
        guard valid else {
            throw ProfileRecordValidationError.invalidObservation
        }
        self.result = result
        self.source = source
        self.awakeSecondsObserved = awakeSecondsObserved
        self.maxGapSeconds = maxGapSeconds
        self.targetAbsentAtEnd = targetAbsentAtEnd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            result: container.decode(PreferenceObservationResultV1.self, forKey: .result),
            source: container.decode(PreferenceObservationSourceV1.self, forKey: .source),
            awakeSecondsObserved: container.decode(UInt.self, forKey: .awakeSecondsObserved),
            maxGapSeconds: container.decode(UInt.self, forKey: .maxGapSeconds),
            targetAbsentAtEnd: container.decode(Bool.self, forKey: .targetAbsentAtEnd)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case result
        case source
        case awakeSecondsObserved
        case maxGapSeconds
        case targetAbsentAtEnd
    }
}

public enum BlockingCapabilityV1: String, Codable, Equatable, Sendable {
    case strongReady
    case notGuaranteed
    case pendingGate
    case measurementOnly
    case sharedInterfaceSSID
    case authorizationUnavailable
}

public enum AuthorizationOutcomeV1: String, Codable, Equatable, Sendable {
    case neverRequested
    case granted
    case denied
    case unavailable
    case invalidated
}

public enum ProtectionFailureReasonV1: String, Codable, Equatable, Sendable {
    case counterReadFailed
    case targetIdentityChanged
    case disconnectUnverified
    case authorizationDenied
    case preferenceCommitFailed
    case preferenceReadBackFailed
    case restorationConflict
    case restorationUnverified
    case storageFailure
    case releaseGatePending
    case permissionRequired
    case timeAdjustmentRequired
}

public struct ProtectionRecord: Codable, Equatable, Sendable {
    public let limitReached: Bool
    public let pauseBlocking: Bool
    public let blockingCapability: BlockingCapabilityV1
    public let lastAuthorizationOutcome: AuthorizationOutcomeV1
    public let retry: RetryRecord
    public let lastSuppressionObservation: ObservationSummaryRecord?
    public let lastFailureReason: ProtectionFailureReasonV1?
    public let ownedTransactionID: UUID?

    public init(
        limitReached: Bool,
        pauseBlocking: Bool,
        blockingCapability: BlockingCapabilityV1,
        lastAuthorizationOutcome: AuthorizationOutcomeV1,
        retry: RetryRecord,
        lastSuppressionObservation: ObservationSummaryRecord?,
        lastFailureReason: ProtectionFailureReasonV1?,
        ownedTransactionID: UUID?
    ) throws {
        self.limitReached = limitReached
        self.pauseBlocking = pauseBlocking
        self.blockingCapability = blockingCapability
        self.lastAuthorizationOutcome = lastAuthorizationOutcome
        self.retry = retry
       self.lastSuppressionObservation = lastSuppressionObservation
       self.lastFailureReason = lastFailureReason
       self.ownedTransactionID = ownedTransactionID
   }

    public func updating(
        limitReached: Bool? = nil,
        pauseBlocking: Bool? = nil,
        blockingCapability: BlockingCapabilityV1? = nil,
        lastAuthorizationOutcome: AuthorizationOutcomeV1? = nil,
        retry: RetryRecord? = nil,
        lastSuppressionObservation: ObservationSummaryRecord?? = nil,
        lastFailureReason: ProtectionFailureReasonV1?? = nil,
        ownedTransactionID: UUID?? = nil
    ) throws -> ProtectionRecord {
        try ProtectionRecord(
            limitReached: limitReached ?? self.limitReached,
            pauseBlocking: pauseBlocking ?? self.pauseBlocking,
            blockingCapability: blockingCapability ?? self.blockingCapability,
            lastAuthorizationOutcome: lastAuthorizationOutcome ?? self.lastAuthorizationOutcome,
            retry: retry ?? self.retry,
            lastSuppressionObservation: lastSuppressionObservation != nil ? lastSuppressionObservation! : self.lastSuppressionObservation,
            lastFailureReason: lastFailureReason != nil ? lastFailureReason! : self.lastFailureReason,
            ownedTransactionID: ownedTransactionID != nil ? ownedTransactionID! : self.ownedTransactionID
        )
    }

   public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.lastSuppressionObservation),
              container.contains(.lastFailureReason),
              container.contains(.ownedTransactionID) else {
            throw ProfileRecordValidationError.invalidObservation
        }
        try self.init(
            limitReached: container.decode(Bool.self, forKey: .limitReached),
            pauseBlocking: container.decode(Bool.self, forKey: .pauseBlocking),
            blockingCapability: container.decode(
                BlockingCapabilityV1.self,
                forKey: .blockingCapability
            ),
            lastAuthorizationOutcome: container.decode(
                AuthorizationOutcomeV1.self,
                forKey: .lastAuthorizationOutcome
            ),
            retry: container.decode(RetryRecord.self, forKey: .retry),
            lastSuppressionObservation: container.decodeIfPresent(
                ObservationSummaryRecord.self,
                forKey: .lastSuppressionObservation
            ),
            lastFailureReason: container.decodeIfPresent(
                ProtectionFailureReasonV1.self,
                forKey: .lastFailureReason
            ),
            ownedTransactionID: container.decodeIfPresent(UUID.self, forKey: .ownedTransactionID)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(limitReached, forKey: .limitReached)
        try container.encode(pauseBlocking, forKey: .pauseBlocking)
        try container.encode(blockingCapability, forKey: .blockingCapability)
        try container.encode(lastAuthorizationOutcome, forKey: .lastAuthorizationOutcome)
        try container.encode(retry, forKey: .retry)
        try encodeExplicitOptional(
            lastSuppressionObservation,
            in: &container,
            forKey: .lastSuppressionObservation
        )
        try encodeExplicitOptional(lastFailureReason, in: &container, forKey: .lastFailureReason)
        try encodeExplicitOptional(ownedTransactionID, in: &container, forKey: .ownedTransactionID)
    }

    private enum CodingKeys: String, CodingKey {
        case limitReached
        case pauseBlocking
        case blockingCapability
        case lastAuthorizationOutcome
        case retry
        case lastSuppressionObservation
        case lastFailureReason
        case ownedTransactionID
    }
}
