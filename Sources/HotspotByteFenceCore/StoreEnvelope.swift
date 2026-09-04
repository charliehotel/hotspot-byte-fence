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
    case profileNotFound
    case integrityDigestMismatch
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

    public func unhashed() throws -> StoreEnvelopeV1 {
        try StoreEnvelopeV1(
            storeRevision: storeRevision,
            previousGoodRevision: previousGoodRevision,
            installationID: installationID,
            hasCompletedProfile: hasCompletedProfile,
            observedArtifact: observedArtifact,
            globalState: globalState,
            selectedProfileID: selectedProfileID,
            languageOverride: languageOverride,
            profiles: profiles,
            preferenceTransactions: preferenceTransactions,
            commandResults: commandResults,
            notificationState: notificationState,
            eventLog: eventLog,
            tombstoneDigest: tombstoneDigest,
            integrity: try integrity.unhashed()
        )
    }

    public func canonicalStoreDigest() throws -> String {
        let unhashedEnvelope = try unhashed()
        let data = try StoreJSONCodec.encode(unhashedEnvelope)
        return StoreJSONCodec.sha256Hex(data)
    }

    public func withSelfBoundDigest(
        lkgDigest: String? = nil,
        validatedAt: Date? = nil
    ) throws -> StoreEnvelopeV1 {
        let effectiveDate = validatedAt ?? integrity.validatedAt
        let unhashedIntegrity = try IntegrityRecord(
            algorithm: IntegrityRecord.algorithm,
            canonicalDigest: nil,
            lkgDigest: nil,
            lastValidatedRevision: storeRevision,
            previousValidatedRevision: previousGoodRevision,
            validatedAt: effectiveDate
        )
        let unhashedEnvelope = try StoreEnvelopeV1(
            storeRevision: storeRevision,
            previousGoodRevision: previousGoodRevision,
            installationID: installationID,
            hasCompletedProfile: hasCompletedProfile,
            observedArtifact: observedArtifact,
            globalState: globalState,
            selectedProfileID: selectedProfileID,
            languageOverride: languageOverride,
            profiles: profiles,
            preferenceTransactions: preferenceTransactions,
            commandResults: commandResults,
            notificationState: notificationState,
            eventLog: eventLog,
            tombstoneDigest: tombstoneDigest,
            integrity: unhashedIntegrity
        )
        let digest = try unhashedEnvelope.canonicalStoreDigest()
        let newIntegrity = try IntegrityRecord(
            algorithm: IntegrityRecord.algorithm,
            canonicalDigest: digest,
            lkgDigest: lkgDigest,
            lastValidatedRevision: storeRevision,
            previousValidatedRevision: previousGoodRevision,
            validatedAt: effectiveDate
        )
        return try StoreEnvelopeV1(
            storeRevision: storeRevision,
            previousGoodRevision: previousGoodRevision,
            installationID: installationID,
            hasCompletedProfile: hasCompletedProfile,
            observedArtifact: observedArtifact,
            globalState: globalState,
            selectedProfileID: selectedProfileID,
            languageOverride: languageOverride,
            profiles: profiles,
            preferenceTransactions: preferenceTransactions,
            commandResults: commandResults,
            notificationState: notificationState,
            eventLog: eventLog,
           tombstoneDigest: tombstoneDigest,
           integrity: newIntegrity
       )
   }

    public func updatingStore(
        now: Date = Date(),
        globalState: GlobalStateRecord? = nil,
        selectedProfileID: UUID?? = nil,
        languageOverride: StoreLanguageOverrideV1? = nil,
        profiles: [ProfileRecord]? = nil,
        preferenceTransactions: [PreferenceTransactionRecord]? = nil,
        commandResults: [CommandResultRecord]? = nil,
        notificationState: NotificationStateRecord? = nil,
        eventLog: EventLogRecord? = nil
    ) throws -> StoreEnvelopeV1 {
        let canonicalNow = Date(timeIntervalSince1970: (now.timeIntervalSince1970 * 1000).rounded() / 1000)
        let newRevision = DecimalUInt64(rawValue: storeRevision.rawValue + 1)
        let resolvedProfiles = profiles ?? self.profiles
        let hasCompleted = resolvedProfiles.contains(where: \.isComplete)
        let resolvedSelectedProfileID: UUID?
        if let selectedProfileID {
            resolvedSelectedProfileID = selectedProfileID
        } else {
            resolvedSelectedProfileID = self.selectedProfileID
        }

        let interimIntegrity = try IntegrityRecord(
            algorithm: IntegrityRecord.algorithm,
            canonicalDigest: nil,
            lkgDigest: integrity.canonicalDigest,
            lastValidatedRevision: newRevision,
            previousValidatedRevision: storeRevision,
            validatedAt: canonicalNow
        )

        let interimEnvelope = try StoreEnvelopeV1(
            storeRevision: newRevision,
            previousGoodRevision: storeRevision,
            installationID: installationID,
            hasCompletedProfile: hasCompleted,
            observedArtifact: observedArtifact,
            globalState: globalState ?? self.globalState,
            selectedProfileID: resolvedSelectedProfileID,
            languageOverride: languageOverride ?? self.languageOverride,
            profiles: resolvedProfiles,
            preferenceTransactions: preferenceTransactions ?? self.preferenceTransactions,
            commandResults: commandResults ?? self.commandResults,
            notificationState: notificationState ?? self.notificationState,
            eventLog: eventLog ?? self.eventLog,
            tombstoneDigest: tombstoneDigest,
            integrity: interimIntegrity
        )

        return try interimEnvelope.withSelfBoundDigest(
            lkgDigest: integrity.canonicalDigest,
            validatedAt: canonicalNow
        )
    }

   public func validateSelfBinding() throws {
        guard let canonicalDigest = integrity.canonicalDigest else {
            throw StoreEnvelopeValidationError.integrityDigestMismatch
        }
        let expectedDigest = try canonicalStoreDigest()
        guard canonicalDigest == expectedDigest else {
            throw StoreEnvelopeValidationError.integrityDigestMismatch
        }
    }

    public func purgingProfile(
        id: UUID,
        newRevision: DecimalUInt64,
        deletedAt: Date = Date(),
        tombstoneDigest: String
    ) throws -> StoreEnvelopeV1 {
        guard profiles.contains(where: { $0.profileID == id }) else {
            throw StoreEnvelopeValidationError.profileNotFound
        }
        guard newRevision.rawValue > storeRevision.rawValue else {
            throw StoreEnvelopeValidationError.invalidRevision
        }
        guard PersistenceDigest.isValid(tombstoneDigest) else {
            throw StoreEnvelopeValidationError.invalidTombstoneDigest
        }

        let updatedProfiles = profiles.filter { $0.profileID != id }
        let updatedTransactions = preferenceTransactions.filter { $0.profileID != id }
        let updatedNotificationStates = notificationState.profileNotificationStates.filter { $0.key != id }
        let updatedNotificationState = NotificationStateRecord(
            profileNotificationStates: updatedNotificationStates,
            systemAuthorization: notificationState.systemAuthorization
        )

        let deletedTransactionIDs = Set(preferenceTransactions.filter { $0.profileID == id }.map(\.transactionID))
        var remainingEvents = eventLog.events.filter { event in
            if event.profileID == id { return false }
            if let txID = event.transactionID, deletedTransactionIDs.contains(txID) { return false }
            return true
        }

        let nextSequence = DecimalUInt64(rawValue: (remainingEvents.last?.sequence.rawValue ?? 0) + 1)
        let deletionEvent = try EventRecord(
            sequence: nextSequence,
            storeRevision: newRevision,
            occurredAt: deletedAt,
            profileID: nil,
            transactionID: nil,
            kind: .profileDeletion,
            redactionClass: .public,
            details: EventDetailsV1(
                reason: .profileDeleted,
                oldState: "active",
                newState: "purged",
                storeRevision: newRevision
            )
        )
        remainingEvents.append(deletionEvent)
        let updatedEventLog = try EventLogRecord(
            retentionPolicy: eventLog.retentionPolicy,
            events: remainingEvents
        )

        let updatedSelectedProfileID = (selectedProfileID == id) ? nil : selectedProfileID
        let hasCompleted = updatedProfiles.contains(where: \.isComplete)

        let interimIntegrity = try IntegrityRecord(
            algorithm: IntegrityRecord.algorithm,
            canonicalDigest: nil,
            lkgDigest: integrity.canonicalDigest,
            lastValidatedRevision: newRevision,
            previousValidatedRevision: storeRevision,
            validatedAt: deletedAt
        )

        let interimEnvelope = try StoreEnvelopeV1(
            storeRevision: newRevision,
            previousGoodRevision: storeRevision,
            installationID: installationID,
            hasCompletedProfile: hasCompleted,
            observedArtifact: observedArtifact,
            globalState: globalState,
            selectedProfileID: updatedSelectedProfileID,
            languageOverride: languageOverride,
            profiles: updatedProfiles,
            preferenceTransactions: updatedTransactions,
            commandResults: commandResults,
            notificationState: updatedNotificationState,
            eventLog: updatedEventLog,
            tombstoneDigest: tombstoneDigest,
            integrity: interimIntegrity
        )

        return try interimEnvelope.withSelfBoundDigest(
            lkgDigest: integrity.canonicalDigest,
            validatedAt: deletedAt
        )
    }

    public static func makeInitial(
        installationID: UUID,
        observedArtifact: ArtifactObservationRecord? = nil
    ) throws -> StoreEnvelopeV1 {
        let revision = DecimalUInt64(rawValue: 1)
        let effectiveArtifact: ArtifactObservationRecord
        if let observedArtifact {
            effectiveArtifact = observedArtifact
        } else {
            effectiveArtifact = try ArtifactObservationRecord(
                compiledModeObserved: .measurementOnly,
                buildManifestSHA256: String(repeating: "0", count: 64),
                codeSignatureStatus: .unsigned,
                hardenedRuntimeStatus: .unavailable,
                notarizationStatus: .notApplicable,
                gatekeeperStatus: .notApplicable,
                quarantineStatus: .absent,
                macOSBuild: "unknown",
                observedAt: Date()
            )
        }
        let integrity = try IntegrityRecord(
            algorithm: IntegrityRecord.algorithm,
            canonicalDigest: nil,
            lkgDigest: nil,
            lastValidatedRevision: revision,
            previousValidatedRevision: nil,
            validatedAt: Date()
        )
        let emptyTombstones = try TombstoneSetV1(records: [])
        let tombstoneDigest = try emptyTombstones.canonicalDigest()
        let envelope = try StoreEnvelopeV1(
            storeRevision: revision,
            previousGoodRevision: nil,
            installationID: installationID,
            hasCompletedProfile: false,
            observedArtifact: effectiveArtifact,
            globalState: try GlobalStateRecord(
                safetyState: .normal,
                recoveryReason: nil,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            ),
            selectedProfileID: nil,
            languageOverride: .system,
            profiles: [],
            preferenceTransactions: [],
            commandResults: [],
            notificationState: NotificationStateRecord(),
            eventLog: try EventLogRecord(events: []),
            tombstoneDigest: tombstoneDigest,
            integrity: integrity
        )
        return try envelope.withSelfBoundDigest()
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
