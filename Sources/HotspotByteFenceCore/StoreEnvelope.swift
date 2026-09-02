import Foundation

public enum StoreEnvelopeValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidRevision
    case invalidTombstoneDigest
    case duplicateTransactionID
    case invalidTransaction
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
    public let selectedProfileID: UUID?
    public let languageOverride: StoreLanguageOverrideV1
    public let preferenceTransactions: [PreferenceTransactionRecord]
    public let tombstoneDigest: String

    public init(
        storeRevision: DecimalUInt64,
        previousGoodRevision: DecimalUInt64? = nil,
        installationID: UUID,
        hasCompletedProfile: Bool,
        selectedProfileID: UUID? = nil,
        languageOverride: StoreLanguageOverrideV1,
        preferenceTransactions: [PreferenceTransactionRecord],
        tombstoneDigest: String
    ) throws {
        self.schemaVersion = 1
        self.storeRevision = storeRevision
        self.previousGoodRevision = previousGoodRevision
        self.installationID = installationID
        self.hasCompletedProfile = hasCompletedProfile
        self.selectedProfileID = selectedProfileID
        self.languageOverride = languageOverride
        self.preferenceTransactions = preferenceTransactions
        self.tombstoneDigest = tombstoneDigest
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt.self, forKey: .schemaVersion) == 1 else {
            throw StoreEnvelopeValidationError.unsupportedSchemaVersion
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
        try self.init(
            storeRevision: container.decode(DecimalUInt64.self, forKey: .storeRevision),
            previousGoodRevision: container.decodeIfPresent(
                DecimalUInt64.self,
                forKey: .previousGoodRevision
            ),
            installationID: container.decode(UUID.self, forKey: .installationID),
            hasCompletedProfile: container.decode(Bool.self, forKey: .hasCompletedProfile),
            selectedProfileID: container.decodeIfPresent(UUID.self, forKey: .selectedProfileID),
            languageOverride: container.decode(
                StoreLanguageOverrideV1.self,
                forKey: .languageOverride
            ),
            preferenceTransactions: transactions,
            tombstoneDigest: container.decode(String.self, forKey: .tombstoneDigest)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(storeRevision, forKey: .storeRevision)
        if let previousGoodRevision {
            try container.encode(previousGoodRevision, forKey: .previousGoodRevision)
        } else {
            try container.encodeNil(forKey: .previousGoodRevision)
        }
        try container.encode(installationID, forKey: .installationID)
        try container.encode(hasCompletedProfile, forKey: .hasCompletedProfile)
        if let selectedProfileID {
            try container.encode(selectedProfileID, forKey: .selectedProfileID)
        } else {
            try container.encodeNil(forKey: .selectedProfileID)
        }
        try container.encode(languageOverride, forKey: .languageOverride)
        try container.encode(preferenceTransactions, forKey: .preferenceTransactions)
        try container.encode(tombstoneDigest, forKey: .tombstoneDigest)
    }

    private func validate() throws {
        if let previousGoodRevision,
           previousGoodRevision.rawValue >= storeRevision.rawValue {
            throw StoreEnvelopeValidationError.invalidRevision
        }
        guard PersistenceDigest.isValid(tombstoneDigest) else {
            throw StoreEnvelopeValidationError.invalidTombstoneDigest
        }
        let transactionIDs = preferenceTransactions.map(\.transactionID)
        guard Set(transactionIDs).count == transactionIDs.count else {
            throw StoreEnvelopeValidationError.duplicateTransactionID
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case storeRevision
        case previousGoodRevision
        case installationID
        case hasCompletedProfile
        case selectedProfileID
        case languageOverride
        case preferenceTransactions
        case tombstoneDigest
    }
}
