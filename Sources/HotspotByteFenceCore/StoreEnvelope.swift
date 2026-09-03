import Foundation

public enum StoreEnvelopeValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidRevision
    case invalidTombstoneDigest
    case duplicateTransactionID
    case invalidTransaction
    case invalidProfile
    case invalidGlobalState
    case invalidIntegrity
    case invalidArtifactObservation
    case invalidCommandResult
    case invalidNotificationState
    case invalidEventLog
    case duplicateProfileID
    case duplicateProfileAlias
    case selectedProfileMissing
    case transactionProfileMissing
    case ownedTransactionMismatch
    case notificationProfileMissing
    case eventProfileMissing
    case duplicateCommandIdempotencyKey
    case missingNullableField
}

public enum StoreLanguageOverrideV1: String, Codable, Equatable, Sendable {
    case system
    case ko
    case en
}

public struct StoreEnvelopeV1: Codable, Equatable, Sendable, VersionedDocument {
    public let schemaVersion: UInt
    public let storeRevision: DecimalUInt64
    public let previousGoodRevision: DecimalUInt64?
    public let installationID: UUID
    public let hasCompletedProfile: Bool
    public let observedArtifact: ArtifactObservationRecord
    public let globalState: GlobalStateRecord
    public let selectedProfileID: UUID?
    public let languageOverride: StoreLanguageOverrideV1
    public let profiles: [ProfileRecord]
    public let preferenceTransactions: [PreferenceTransactionRecord]
    public let commandResults: [CommandResultRecord]
    public let notificationState: NotificationStateRecord
    public let eventLog: EventLogRecord
    public let tombstoneDigest: String
    public let integrity: IntegrityRecord

    public init(
        storeRevision: DecimalUInt64,
        previousGoodRevision: DecimalUInt64? = nil,
        installationID: UUID,
        hasCompletedProfile: Bool,
        observedArtifact: ArtifactObservationRecord,
        globalState: GlobalStateRecord,
        selectedProfileID: UUID? = nil,
        languageOverride: StoreLanguageOverrideV1,
        profiles: [ProfileRecord],
        preferenceTransactions: [PreferenceTransactionRecord] = [],
        commandResults: [CommandResultRecord] = [],
        notificationState: NotificationStateRecord = NotificationStateRecord(),
        eventLog: EventLogRecord,
        tombstoneDigest: String,
        integrity: IntegrityRecord
    ) throws {
        self.schemaVersion = 1
        self.storeRevision = storeRevision
        self.previousGoodRevision = previousGoodRevision
        self.installationID = installationID
        self.hasCompletedProfile = hasCompletedProfile
        self.observedArtifact = observedArtifact
        self.globalState = globalState
        self.selectedProfileID = selectedProfileID
        self.languageOverride = languageOverride
        self.profiles = profiles
        self.preferenceTransactions = preferenceTransactions
        self.commandResults = commandResults
        self.notificationState = notificationState
        self.eventLog = eventLog
        self.tombstoneDigest = tombstoneDigest
        self.integrity = integrity
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt.self, forKey: .schemaVersion) == 1 else {
            throw StoreEnvelopeValidationError.unsupportedSchemaVersion
        }
        guard container.contains(.previousGoodRevision),
              container.contains(.selectedProfileID) else {
            throw StoreEnvelopeValidationError.missingNullableField
        }

        let observedArtifact: ArtifactObservationRecord
        do {
            observedArtifact = try container.decode(
                ArtifactObservationRecord.self,
                forKey: .observedArtifact
            )
        } catch {
            throw StoreEnvelopeValidationError.invalidArtifactObservation
        }

        let profiles: [ProfileRecord]
        do {
            profiles = try container.decode([ProfileRecord].self, forKey: .profiles)
        } catch {
            throw StoreEnvelopeValidationError.invalidProfile
        }

        let globalState: GlobalStateRecord
        do {
            globalState = try container.decode(GlobalStateRecord.self, forKey: .globalState)
        } catch {
            throw StoreEnvelopeValidationError.invalidGlobalState
        }

        let integrity: IntegrityRecord
        do {
            integrity = try container.decode(IntegrityRecord.self, forKey: .integrity)
        } catch {
            throw StoreEnvelopeValidationError.invalidIntegrity
        }

        let transactions: [PreferenceTransactionRecord]
        do {
            transactions = try container.decode(
                [PreferenceTransactionRecord].self,
                forKey: .preferenceTransactions
            )
        } catch {
            throw StoreEnvelopeValidationError.invalidTransaction
        }

        let commandResults: [CommandResultRecord]
        do {
            commandResults = try container.decode(
                [CommandResultRecord].self,
                forKey: .commandResults
            )
        } catch {
            throw StoreEnvelopeValidationError.invalidCommandResult
        }

        let notificationState: NotificationStateRecord
        do {
            notificationState = try container.decode(
                NotificationStateRecord.self,
                forKey: .notificationState
            )
        } catch {
            throw StoreEnvelopeValidationError.invalidNotificationState
        }

        let eventLog: EventLogRecord
        do {
            eventLog = try container.decode(EventLogRecord.self, forKey: .eventLog)
        } catch {
            throw StoreEnvelopeValidationError.invalidEventLog
        }

        try self.init(
            storeRevision: container.decode(DecimalUInt64.self, forKey: .storeRevision),
            previousGoodRevision: container.decodeIfPresent(
                DecimalUInt64.self,
                forKey: .previousGoodRevision
            ),
            installationID: container.decode(UUID.self, forKey: .installationID),
            hasCompletedProfile: container.decode(Bool.self, forKey: .hasCompletedProfile),
            observedArtifact: observedArtifact,
            globalState: globalState,
            selectedProfileID: container.decodeIfPresent(UUID.self, forKey: .selectedProfileID),
            languageOverride: container.decode(
                StoreLanguageOverrideV1.self,
                forKey: .languageOverride
            ),
            profiles: profiles,
            preferenceTransactions: transactions,
            commandResults: commandResults,
            notificationState: notificationState,
            eventLog: eventLog,
            tombstoneDigest: container.decode(String.self, forKey: .tombstoneDigest),
            integrity: integrity
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(storeRevision, forKey: .storeRevision)
        try encodeExplicitOptional(previousGoodRevision, in: &container, forKey: .previousGoodRevision)
        try container.encode(installationID, forKey: .installationID)
        try container.encode(hasCompletedProfile, forKey: .hasCompletedProfile)
        try container.encode(observedArtifact, forKey: .observedArtifact)
        try container.encode(globalState, forKey: .globalState)
        try encodeExplicitOptional(selectedProfileID, in: &container, forKey: .selectedProfileID)
        try container.encode(languageOverride, forKey: .languageOverride)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(preferenceTransactions, forKey: .preferenceTransactions)
        try container.encode(commandResults, forKey: .commandResults)
        try container.encode(notificationState, forKey: .notificationState)
        try container.encode(eventLog, forKey: .eventLog)
        try container.encode(tombstoneDigest, forKey: .tombstoneDigest)
        try container.encode(integrity, forKey: .integrity)
    }

    private func validate() throws {
        if let previousGoodRevision,
           previousGoodRevision.rawValue >= storeRevision.rawValue {
            throw StoreEnvelopeValidationError.invalidRevision
        }
        guard PersistenceDigest.isValid(tombstoneDigest) else {
            throw StoreEnvelopeValidationError.invalidTombstoneDigest
        }
        let profileIDs = profiles.map(\.profileID)
        guard Set(profileIDs).count == profileIDs.count else {
            throw StoreEnvelopeValidationError.duplicateProfileID
        }
        let aliases = profiles.map(\.aliasNFC)
        guard Set(aliases).count == aliases.count else {
            throw StoreEnvelopeValidationError.duplicateProfileAlias
        }
        if let selectedProfileID, !profileIDs.contains(selectedProfileID) {
            throw StoreEnvelopeValidationError.selectedProfileMissing
        }
        guard preferenceTransactions.allSatisfy({ profileIDs.contains($0.profileID) }) else {
            throw StoreEnvelopeValidationError.transactionProfileMissing
        }
        let transactionIDs = preferenceTransactions.map(\.transactionID)
        guard Set(transactionIDs).count == transactionIDs.count else {
            throw StoreEnvelopeValidationError.duplicateTransactionID
        }
        for profile in profiles {
            if let ownedID = profile.protection.ownedTransactionID {
                guard let transaction = preferenceTransactions.first(where: { $0.transactionID == ownedID }),
                      transaction.profileID == profile.profileID,
                      profile.interfaceName == nil || transaction.targetScope.interfaceName == profile.interfaceName else {
                    throw StoreEnvelopeValidationError.ownedTransactionMismatch
                }
            }
        }
        for profileID in notificationState.profileNotificationStates.keys {
            guard profileIDs.contains(profileID) else {
                throw StoreEnvelopeValidationError.notificationProfileMissing
            }
        }
        var seenCommandKeys = Set<String>()
        for command in commandResults {
            let key = "\(command.commandName.rawValue):\(command.idempotencyKey.uuidString)"
            guard seenCommandKeys.insert(key).inserted else {
                throw StoreEnvelopeValidationError.duplicateCommandIdempotencyKey
            }
        }
        for event in eventLog.events {
            if let profileID = event.profileID {
                guard profileIDs.contains(profileID) else {
                    throw StoreEnvelopeValidationError.eventProfileMissing
                }
            }
        }
        guard integrity.lastValidatedRevision == storeRevision,
              integrity.previousValidatedRevision == previousGoodRevision else {
            throw StoreEnvelopeValidationError.invalidIntegrity
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case storeRevision
        case previousGoodRevision
        case installationID
        case hasCompletedProfile
        case observedArtifact
        case globalState
        case selectedProfileID
        case languageOverride
        case profiles
        case preferenceTransactions
        case commandResults
        case notificationState
        case eventLog
        case tombstoneDigest
        case integrity
    }
}
