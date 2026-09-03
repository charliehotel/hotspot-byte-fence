import Foundation

public enum CommandNameV1: String, Codable, Equatable, Sendable, CaseIterable {
    case createProfileFromCurrentNetwork
    case createProfileManualIdentity
    case appendBSSID
    case selectProfile
    case togglePauseBlocking
    case manualResetUsage
    case changeLimit
    case changeResetDay
    case requestBlockingAuthorization
    case recordManualReconnectIntent
    case retryRestoration
    case muteFailureNotification
    case deleteProfile
    case quitApplication
}

public enum CommandOutcomeV1: String, Codable, Equatable, Sendable {
    case succeeded
    case cancelled
    case rejected
    case failed
}

public enum CommandResultCodeV1: String, Codable, Equatable, Sendable {
    case success
    case cancelled
    case staleSnapshot
    case validationFailed
    case permissionRequired
    case authorizationRequired
    case conflict
    case unverified
    case recoveryRequired
    case notFound
    case ineligible
}

public enum CommandResultRecordValidationError: Error, Equatable, Sendable {
    case invalidDigest
    case invalidDate
}

public struct CommandResultRecord: Codable, Equatable, Sendable {
    public let commandName: CommandNameV1
    public let idempotencyKey: UUID
    public let outcome: CommandOutcomeV1
    public let resultCode: CommandResultCodeV1
    public let storeRevision: DecimalUInt64
    public let resultDigest: String
    public let recordedAt: Date

    public init(
        commandName: CommandNameV1,
        idempotencyKey: UUID,
        outcome: CommandOutcomeV1,
        resultCode: CommandResultCodeV1,
        storeRevision: DecimalUInt64,
        resultDigest: String,
        recordedAt: Date
    ) throws {
        self.commandName = commandName
        self.idempotencyKey = idempotencyKey
        self.outcome = outcome
        self.resultCode = resultCode
        self.storeRevision = storeRevision
        self.resultDigest = resultDigest
        self.recordedAt = recordedAt
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            commandName: container.decode(CommandNameV1.self, forKey: .commandName),
            idempotencyKey: container.decode(UUID.self, forKey: .idempotencyKey),
            outcome: container.decode(CommandOutcomeV1.self, forKey: .outcome),
            resultCode: container.decode(CommandResultCodeV1.self, forKey: .resultCode),
            storeRevision: container.decode(DecimalUInt64.self, forKey: .storeRevision),
            resultDigest: container.decode(String.self, forKey: .resultDigest),
            recordedAt: container.decode(Date.self, forKey: .recordedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandName, forKey: .commandName)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(resultCode, forKey: .resultCode)
        try container.encode(resultDigest, forKey: .resultDigest)
        try container.encode(storeRevision, forKey: .storeRevision)
    }

    private func validate() throws {
        guard PersistenceDigest.isValid(resultDigest) else {
            throw CommandResultRecordValidationError.invalidDigest
        }
        guard recordedAt.timeIntervalSince1970.isFinite else {
            throw CommandResultRecordValidationError.invalidDate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case commandName
        case idempotencyKey
        case outcome
        case recordedAt
        case resultCode
        case resultDigest
        case storeRevision
    }
}

