import Foundation

public enum SystemNotificationAuthorizationV1: String, Codable, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case unknown
}

public enum ProfileFailureMuteV1: String, Codable, Equatable, Sendable {
    case none
    case untilInstant
    case untilCycleEnds
}

public enum ProfileNotificationRecordValidationError: Error, Equatable, Sendable {
    case invalidDate
    case invalidMuteState
    case missingNullableField
}

public struct ProfileNotificationRecord: Codable, Equatable, Sendable {
    public let successNotifiedCycleDate: String?
    public let failureMute: ProfileFailureMuteV1
    public let muteExpiresAt: Date?
    public let muteCycleDate: String?
    public let lastFailureNotificationAt: Date?

    public init(
        successNotifiedCycleDate: String? = nil,
        failureMute: ProfileFailureMuteV1 = .none,
        muteExpiresAt: Date? = nil,
        muteCycleDate: String? = nil,
        lastFailureNotificationAt: Date? = nil
    ) throws {
        self.successNotifiedCycleDate = successNotifiedCycleDate
        self.failureMute = failureMute
        self.muteExpiresAt = muteExpiresAt
        self.muteCycleDate = muteCycleDate
        self.lastFailureNotificationAt = lastFailureNotificationAt
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.successNotifiedCycleDate),
              container.contains(.muteExpiresAt),
              container.contains(.muteCycleDate),
              container.contains(.lastFailureNotificationAt) else {
            throw ProfileNotificationRecordValidationError.missingNullableField
        }
        try self.init(
            successNotifiedCycleDate: container.decodeIfPresent(
                String.self,
                forKey: .successNotifiedCycleDate
            ),
            failureMute: container.decode(ProfileFailureMuteV1.self, forKey: .failureMute),
            muteExpiresAt: container.decodeIfPresent(Date.self, forKey: .muteExpiresAt),
            muteCycleDate: container.decodeIfPresent(String.self, forKey: .muteCycleDate),
            lastFailureNotificationAt: container.decodeIfPresent(
                Date.self,
                forKey: .lastFailureNotificationAt
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(failureMute, forKey: .failureMute)
        try encodeExplicitOptional(
            lastFailureNotificationAt,
            in: &container,
            forKey: .lastFailureNotificationAt
        )
        try encodeExplicitOptional(muteCycleDate, in: &container, forKey: .muteCycleDate)
        try encodeExplicitOptional(muteExpiresAt, in: &container, forKey: .muteExpiresAt)
        try encodeExplicitOptional(
            successNotifiedCycleDate,
            in: &container,
            forKey: .successNotifiedCycleDate
        )
    }

    private func validate() throws {
        if let successNotifiedCycleDate {
            guard PersistenceDateValidation.isCanonicalDate(successNotifiedCycleDate) else {
                throw ProfileNotificationRecordValidationError.invalidDate
            }
        }
        switch failureMute {
        case .none:
            guard muteExpiresAt == nil, muteCycleDate == nil else {
                throw ProfileNotificationRecordValidationError.invalidMuteState
            }
        case .untilInstant:
            guard let muteExpiresAt,
                  muteCycleDate == nil,
                  muteExpiresAt.timeIntervalSince1970.isFinite else {
                throw ProfileNotificationRecordValidationError.invalidMuteState
            }
        case .untilCycleEnds:
            guard let muteCycleDate,
                  muteExpiresAt == nil,
                  PersistenceDateValidation.isCanonicalDate(muteCycleDate) else {
                throw ProfileNotificationRecordValidationError.invalidMuteState
            }
        }
        if let lastFailureNotificationAt {
            guard lastFailureNotificationAt.timeIntervalSince1970.isFinite else {
                throw ProfileNotificationRecordValidationError.invalidDate
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case failureMute
        case lastFailureNotificationAt
        case muteCycleDate
        case muteExpiresAt
        case successNotifiedCycleDate
    }
}

public enum NotificationStateRecordValidationError: Error, Equatable, Sendable {
    case invalidProfileKey
}

public struct NotificationStateRecord: Codable, Equatable, Sendable {
    public let profileNotificationStates: [UUID: ProfileNotificationRecord]
    public let systemAuthorization: SystemNotificationAuthorizationV1

    public init(
        profileNotificationStates: [UUID: ProfileNotificationRecord] = [:],
        systemAuthorization: SystemNotificationAuthorizationV1 = .notDetermined
    ) {
        self.profileNotificationStates = profileNotificationStates
        self.systemAuthorization = systemAuthorization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMap = try container.decode(
            [String: ProfileNotificationRecord].self,
            forKey: .profileNotificationStates
        )
        var states: [UUID: ProfileNotificationRecord] = [:]
        for (key, record) in rawMap {
            guard let uuid = UUID(uuidString: key) else {
                throw NotificationStateRecordValidationError.invalidProfileKey
            }
            states[uuid] = record
        }
        self.profileNotificationStates = states
        self.systemAuthorization = try container.decode(
            SystemNotificationAuthorizationV1.self,
            forKey: .systemAuthorization
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let rawMap = Dictionary(
            uniqueKeysWithValues: profileNotificationStates.map { ($0.key.uuidString, $0.value) }
        )
        try container.encode(rawMap, forKey: .profileNotificationStates)
        try container.encode(systemAuthorization, forKey: .systemAuthorization)
    }

    private enum CodingKeys: String, CodingKey {
        case profileNotificationStates
        case systemAuthorization
    }
}

