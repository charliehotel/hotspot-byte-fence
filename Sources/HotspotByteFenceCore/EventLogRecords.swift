import Foundation

public enum EventRetentionPolicyV1: String, Codable, Equatable, Sendable {
    case currentCyclePlus90Days
}

public enum EventRedactionClassV1: String, Codable, Equatable, Sendable {
    case `public` = "public"
    case localSensitive
    case secretProhibited
}

public enum EventKindV1: String, Codable, Equatable, Sendable, CaseIterable {
    case launch
    case migration
    case storeFailure
    case counterSample
    case counterBaseline
    case counterDiscontinuity
    case cycleTransition
    case timeAdjustment
    case identityResolution
    case permission
    case authorization
    case blockingAttempt
    case blockingFailure
    case preferencePrepared
    case preferenceApplied
    case restorationAttempt
    case restorationConflict
    case restorationResult
    case manualReset
    case limitChange
    case pauseChange
    case profileChange
    case profileDeletion
    case notification
    case lifecycle
    case artifactAudit
    case recovery
}

public enum EventReasonV1: String, Codable, Equatable, Sendable, CaseIterable {
    case profileDeleted
    case launch
    case migration
    case storeFailure
    case counterSample
    case counterBaseline
    case counterDiscontinuity
    case cycleTransition
    case timeAdjustment
    case identityResolution
    case permission
    case authorization
    case blockingAttempt
    case blockingFailure
    case preferencePrepared
    case preferenceApplied
    case restorationAttempt
    case restorationConflict
    case restorationResult
    case manualReset
    case limitChange
    case pauseChange
    case profileChange
    case notification
    case lifecycle
    case artifactAudit
    case recovery
    case firstRun
    case normal
}

public enum EventDetailKey: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case reason
    case oldState
    case newState
    case profileID
    case transactionID
    case storeRevision
    case bytes
    case attemptIndex
    case fingerprint
    case permissionOutcome
    case authorizationOutcome
    case observationOutcome
    case observationSource
    case observationGapSeconds
    case redactionClass
}

public extension EventKindV1 {
    var permittedDetailKeys: Set<EventDetailKey> {
        switch self {
        case .counterSample, .counterBaseline, .counterDiscontinuity:
            return [.profileID, .bytes, .reason, .oldState, .newState]
        case .identityResolution, .permission:
            return [.profileID, .permissionOutcome, .reason, .oldState, .newState]
        case .authorization:
            return [.profileID, .authorizationOutcome, .reason, .oldState, .newState]
        case .blockingAttempt, .blockingFailure:
            return [
                .profileID,
                .transactionID,
                .attemptIndex,
                .reason,
                .oldState,
                .newState,
                .observationOutcome,
                .observationSource,
                .observationGapSeconds
            ]
        case .preferencePrepared, .preferenceApplied, .restorationAttempt, .restorationConflict, .restorationResult:
            return [
                .profileID,
                .transactionID,
                .fingerprint,
                .reason,
                .oldState,
                .newState,
                .observationOutcome,
                .observationSource,
                .observationGapSeconds
            ]
        case .profileChange, .manualReset, .limitChange, .pauseChange:
            return [.profileID, .reason, .oldState, .newState]
        case .profileDeletion:
            return [.reason, .oldState, .newState, .storeRevision]
        case .cycleTransition, .timeAdjustment, .lifecycle, .notification, .artifactAudit, .migration, .recovery, .storeFailure:
            return [.reason, .oldState, .newState, .storeRevision]
        case .launch:
            return [.storeRevision, .reason, .newState]
        }
    }
}

public enum EventValidationError: Error, Equatable, Sendable {
    case secretProhibitedPersisted
    case invalidSequence
    case invalidRevision
    case invalidDate
    case unknownDetailsField(String)
    case disallowedDetailsField(field: String, kind: EventKindV1)
    case missingRequiredDetailsField(field: String, kind: EventKindV1)
    case invalidProfileDeletionEvent
    case profileIDMismatch
    case transactionIDMismatch
    case eventsNotSorted
    case duplicateEventID
    case duplicateSequence
    case missingNullableField
}

public struct EventDetailsV1: Codable, Equatable, Sendable {
    public let reason: EventReasonV1
    public let oldState: String?
    public let newState: String?
    public let profileID: UUID?
    public let transactionID: UUID?
    public let storeRevision: DecimalUInt64?
    public let bytes: DecimalUInt64?
    public let attemptIndex: UInt?
    public let fingerprint: String?
    public let permissionOutcome: String?
    public let authorizationOutcome: String?
    public let observationOutcome: String?
    public let observationSource: String?
    public let observationGapSeconds: UInt?
    public let redactionClass: EventRedactionClassV1?

    public init(
        reason: EventReasonV1,
        oldState: String? = nil,
        newState: String? = nil,
        profileID: UUID? = nil,
        transactionID: UUID? = nil,
        storeRevision: DecimalUInt64? = nil,
        bytes: DecimalUInt64? = nil,
        attemptIndex: UInt? = nil,
        fingerprint: String? = nil,
        permissionOutcome: String? = nil,
        authorizationOutcome: String? = nil,
        observationOutcome: String? = nil,
        observationSource: String? = nil,
        observationGapSeconds: UInt? = nil,
        redactionClass: EventRedactionClassV1? = nil
    ) {
        self.reason = reason
        self.oldState = oldState
        self.newState = newState
        self.profileID = profileID
        self.transactionID = transactionID
        self.storeRevision = storeRevision
        self.bytes = bytes
        self.attemptIndex = attemptIndex
        self.fingerprint = fingerprint
        self.permissionOutcome = permissionOutcome
        self.authorizationOutcome = authorizationOutcome
        self.observationOutcome = observationOutcome
        self.observationSource = observationSource
        self.observationGapSeconds = observationGapSeconds
        self.redactionClass = redactionClass
    }

    public var presentKeys: Set<EventDetailKey> {
        var keys: Set<EventDetailKey> = [.reason]
        if oldState != nil { keys.insert(.oldState) }
        if newState != nil { keys.insert(.newState) }
        if profileID != nil { keys.insert(.profileID) }
        if transactionID != nil { keys.insert(.transactionID) }
        if storeRevision != nil { keys.insert(.storeRevision) }
        if bytes != nil { keys.insert(.bytes) }
        if attemptIndex != nil { keys.insert(.attemptIndex) }
        if fingerprint != nil { keys.insert(.fingerprint) }
        if permissionOutcome != nil { keys.insert(.permissionOutcome) }
        if authorizationOutcome != nil { keys.insert(.authorizationOutcome) }
        if observationOutcome != nil { keys.insert(.observationOutcome) }
        if observationSource != nil { keys.insert(.observationSource) }
        if observationGapSeconds != nil { keys.insert(.observationGapSeconds) }
        if redactionClass != nil { keys.insert(.redactionClass) }
        return keys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        for key in container.allKeys {
            guard EventDetailKey(rawValue: key.stringValue) != nil else {
                throw EventValidationError.unknownDetailsField(key.stringValue)
            }
        }

        let typed = try decoder.container(keyedBy: CodingKeys.self)
        self.reason = try typed.decode(EventReasonV1.self, forKey: .reason)
        self.oldState = try typed.decodeIfPresent(String.self, forKey: .oldState)
        self.newState = try typed.decodeIfPresent(String.self, forKey: .newState)
        self.profileID = try typed.decodeIfPresent(UUID.self, forKey: .profileID)
        self.transactionID = try typed.decodeIfPresent(UUID.self, forKey: .transactionID)
        self.storeRevision = try typed.decodeIfPresent(DecimalUInt64.self, forKey: .storeRevision)
        self.bytes = try typed.decodeIfPresent(DecimalUInt64.self, forKey: .bytes)
        self.attemptIndex = try typed.decodeIfPresent(UInt.self, forKey: .attemptIndex)
        self.fingerprint = try typed.decodeIfPresent(String.self, forKey: .fingerprint)
        self.permissionOutcome = try typed.decodeIfPresent(String.self, forKey: .permissionOutcome)
        self.authorizationOutcome = try typed.decodeIfPresent(String.self, forKey: .authorizationOutcome)
        self.observationOutcome = try typed.decodeIfPresent(String.self, forKey: .observationOutcome)
        self.observationSource = try typed.decodeIfPresent(String.self, forKey: .observationSource)
        self.observationGapSeconds = try typed.decodeIfPresent(UInt.self, forKey: .observationGapSeconds)
        self.redactionClass = try typed.decodeIfPresent(EventRedactionClassV1.self, forKey: .redactionClass)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason, forKey: .reason)
        if let oldState { try container.encode(oldState, forKey: .oldState) }
        if let newState { try container.encode(newState, forKey: .newState) }
        if let profileID { try container.encode(profileID, forKey: .profileID) }
        if let transactionID { try container.encode(transactionID, forKey: .transactionID) }
        if let storeRevision { try container.encode(storeRevision, forKey: .storeRevision) }
        if let bytes { try container.encode(bytes, forKey: .bytes) }
        if let attemptIndex { try container.encode(attemptIndex, forKey: .attemptIndex) }
        if let fingerprint { try container.encode(fingerprint, forKey: .fingerprint) }
        if let permissionOutcome { try container.encode(permissionOutcome, forKey: .permissionOutcome) }
        if let authorizationOutcome { try container.encode(authorizationOutcome, forKey: .authorizationOutcome) }
        if let observationOutcome { try container.encode(observationOutcome, forKey: .observationOutcome) }
        if let observationSource { try container.encode(observationSource, forKey: .observationSource) }
        if let observationGapSeconds { try container.encode(observationGapSeconds, forKey: .observationGapSeconds) }
        if let redactionClass { try container.encode(redactionClass, forKey: .redactionClass) }
    }

    public func validate(for kind: EventKindV1) throws {
        if redactionClass == .secretProhibited {
            throw EventValidationError.secretProhibitedPersisted
        }
        let permitted = kind.permittedDetailKeys
        for key in presentKeys {
            guard permitted.contains(key) else {
                throw EventValidationError.disallowedDetailsField(field: key.rawValue, kind: kind)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case reason
        case oldState
        case newState
        case profileID
        case transactionID
        case storeRevision
        case bytes
        case attemptIndex
        case fingerprint
        case permissionOutcome
        case authorizationOutcome
        case observationOutcome
        case observationSource
        case observationGapSeconds
        case redactionClass
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}

public struct EventRecord: Codable, Equatable, Sendable {
    public let eventID: UUID
    public let sequence: DecimalUInt64
    public let storeRevision: DecimalUInt64
    public let occurredAt: Date
    public let profileID: UUID?
    public let transactionID: UUID?
    public let kind: EventKindV1
    public let redactionClass: EventRedactionClassV1
    public let details: EventDetailsV1

    public init(
        eventID: UUID = UUID(),
        sequence: DecimalUInt64,
        storeRevision: DecimalUInt64,
        occurredAt: Date,
        profileID: UUID? = nil,
        transactionID: UUID? = nil,
        kind: EventKindV1,
        redactionClass: EventRedactionClassV1 = .public,
        details: EventDetailsV1
    ) throws {
        self.eventID = eventID
        self.sequence = sequence
        self.storeRevision = storeRevision
        self.occurredAt = occurredAt
        self.profileID = profileID
        self.transactionID = transactionID
        self.kind = kind
        self.redactionClass = redactionClass
        self.details = details
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.profileID),
              container.contains(.transactionID) else {
            throw EventValidationError.missingNullableField
        }
        try self.init(
            eventID: container.decode(UUID.self, forKey: .eventID),
            sequence: container.decode(DecimalUInt64.self, forKey: .sequence),
            storeRevision: container.decode(DecimalUInt64.self, forKey: .storeRevision),
            occurredAt: container.decode(Date.self, forKey: .occurredAt),
            profileID: container.decodeIfPresent(UUID.self, forKey: .profileID),
            transactionID: container.decodeIfPresent(UUID.self, forKey: .transactionID),
            kind: container.decode(EventKindV1.self, forKey: .kind),
            redactionClass: container.decode(EventRedactionClassV1.self, forKey: .redactionClass),
            details: container.decode(EventDetailsV1.self, forKey: .details)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(details, forKey: .details)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(kind, forKey: .kind)
        try container.encode(occurredAt, forKey: .occurredAt)
        try encodeExplicitOptional(profileID, in: &container, forKey: .profileID)
        try container.encode(redactionClass, forKey: .redactionClass)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(storeRevision, forKey: .storeRevision)
        try encodeExplicitOptional(transactionID, in: &container, forKey: .transactionID)
    }

    private func validate() throws {
        guard redactionClass != .secretProhibited else {
            throw EventValidationError.secretProhibitedPersisted
        }
        guard occurredAt.timeIntervalSince1970.isFinite else {
            throw EventValidationError.invalidDate
        }
        try details.validate(for: kind)

        if kind == .profileDeletion {
            guard profileID == nil,
                  details.profileID == nil,
                  details.reason == .profileDeleted else {
                throw EventValidationError.invalidProfileDeletionEvent
            }
        }
        if let detailProfileID = details.profileID {
            guard detailProfileID == profileID else {
                throw EventValidationError.profileIDMismatch
            }
        }
        if let detailTransactionID = details.transactionID {
            guard detailTransactionID == transactionID else {
                throw EventValidationError.transactionIDMismatch
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case details
        case eventID
        case kind
        case occurredAt
        case profileID
        case redactionClass
        case sequence
        case storeRevision
        case transactionID
    }
}

public struct EventLogRecord: Codable, Equatable, Sendable {
    public let retentionPolicy: EventRetentionPolicyV1
    public let events: [EventRecord]

    public init(
        retentionPolicy: EventRetentionPolicyV1 = .currentCyclePlus90Days,
        events: [EventRecord] = []
    ) throws {
        self.retentionPolicy = retentionPolicy
        self.events = events
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            retentionPolicy: container.decode(EventRetentionPolicyV1.self, forKey: .retentionPolicy),
            events: container.decode([EventRecord].self, forKey: .events)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(retentionPolicy, forKey: .retentionPolicy)
    }

    private func validate() throws {
        var seenIDs = Set<UUID>()
        var lastSequence: UInt64? = nil

        for event in events {
            guard seenIDs.insert(event.eventID).inserted else {
                throw EventValidationError.duplicateEventID
            }
            if let previous = lastSequence {
                guard event.sequence.rawValue > previous else {
                    throw EventValidationError.eventsNotSorted
                }
            }
            lastSequence = event.sequence.rawValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case events
        case retentionPolicy
    }
}
