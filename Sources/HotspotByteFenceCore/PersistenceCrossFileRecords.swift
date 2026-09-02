import Foundation

enum PersistenceDigest {
    static func isValid(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
        }
    }
}

public struct InstallationMarkerV1: Codable, Equatable, Sendable {
    public let schemaVersion: UInt
    public let installationID: UUID
    public let hasCompletedProfile: Bool
    public let firstCompletedStoreRevision: DecimalUInt64
    public let firstCompletedStoreDigest: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        installationID: UUID,
        hasCompletedProfile: Bool,
        firstCompletedStoreRevision: DecimalUInt64,
        firstCompletedStoreDigest: String,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard PersistenceDigest.isValid(firstCompletedStoreDigest) else {
            throw PersistenceError.invalidDigest
        }
        self.schemaVersion = 1
        self.installationID = installationID
        self.hasCompletedProfile = hasCompletedProfile
        self.firstCompletedStoreRevision = firstCompletedStoreRevision
        self.firstCompletedStoreDigest = firstCompletedStoreDigest
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt.self, forKey: .schemaVersion) == 1 else {
            throw PersistenceError.validationFailed
        }
        try self.init(
            installationID: container.decode(UUID.self, forKey: .installationID),
            hasCompletedProfile: container.decode(Bool.self, forKey: .hasCompletedProfile),
            firstCompletedStoreRevision: container.decode(DecimalUInt64.self, forKey: .firstCompletedStoreRevision),
            firstCompletedStoreDigest: container.decode(String.self, forKey: .firstCompletedStoreDigest),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }

    public func matches(
        installationID: UUID,
        canonicalRevision: DecimalUInt64,
        canonicalDigest: String
    ) -> Bool {
        guard self.installationID == installationID,
              schemaVersion == 1,
              PersistenceDigest.isValid(firstCompletedStoreDigest),
              firstCompletedStoreRevision.rawValue <= canonicalRevision.rawValue else {
            return false
        }
        return !hasCompletedProfile || firstCompletedStoreDigest == canonicalDigest
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case installationID
        case hasCompletedProfile
        case firstCompletedStoreRevision
        case firstCompletedStoreDigest
        case createdAt
        case updatedAt
    }
}

public struct TombstoneRecord: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let deletedAt: Date
    public let deletionRevision: DecimalUInt64
    public let aliasDigest: String
    public let purgeCompleted: Bool

    public init(
        profileID: UUID,
        deletedAt: Date,
        deletionRevision: DecimalUInt64,
        aliasDigest: String,
        purgeCompleted: Bool
    ) throws {
        guard PersistenceDigest.isValid(aliasDigest) else {
            throw PersistenceError.invalidDigest
        }
        self.profileID = profileID
        self.deletedAt = deletedAt
        self.deletionRevision = deletionRevision
        self.aliasDigest = aliasDigest
        self.purgeCompleted = purgeCompleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            profileID: container.decode(UUID.self, forKey: .profileID),
            deletedAt: container.decode(Date.self, forKey: .deletedAt),
            deletionRevision: container.decode(DecimalUInt64.self, forKey: .deletionRevision),
            aliasDigest: container.decode(String.self, forKey: .aliasDigest),
            purgeCompleted: container.decode(Bool.self, forKey: .purgeCompleted)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileID
        case deletedAt
        case deletionRevision
        case aliasDigest
        case purgeCompleted
    }
}

public struct TombstoneSetV1: Codable, Equatable, Sendable {
    public let records: [TombstoneRecord]

    public init(records: [TombstoneRecord]) throws {
        let sorted = records.sorted { $0.profileID.uuidString < $1.profileID.uuidString }
        guard Set(sorted.map(\.profileID)).count == sorted.count else {
            throw PersistenceError.duplicateTombstone
        }
        guard Set(sorted.map { $0.purgeCompleted }).count <= 1 else {
            throw PersistenceError.invalidTombstoneState
        }
        self.records = sorted
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var records: [TombstoneRecord] = []
        while !container.isAtEnd {
            records.append(try container.decode(TombstoneRecord.self))
        }
        try self.init(records: records)
    }

    public var isPurgePending: Bool {
        !records.isEmpty && records.allSatisfy { !$0.purgeCompleted }
    }

    public var isPurgeCompleted: Bool {
        records.allSatisfy(\.purgeCompleted)
    }

    public func withPurgeCompleted(_ completed: Bool) -> TombstoneSetV1 {
        TombstoneSetV1(sortedRecords: records.map {
            TombstoneRecord(
                uncheckedProfileID: $0.profileID,
                uncheckedDeletedAt: $0.deletedAt,
                uncheckedDeletionRevision: $0.deletionRevision,
                uncheckedAliasDigest: $0.aliasDigest,
                uncheckedPurgeCompleted: completed
            )
        })
    }

    public func canonicalDigest() throws -> String {
        try StoreJSONCodec.sha256Hex(StoreJSONCodec.encode(self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for record in records {
            try container.encode(record)
        }
    }

    private init(sortedRecords: [TombstoneRecord]) {
        self.records = sortedRecords
    }
}

private extension TombstoneRecord {
    init(
        uncheckedProfileID profileID: UUID,
        uncheckedDeletedAt deletedAt: Date,
        uncheckedDeletionRevision deletionRevision: DecimalUInt64,
        uncheckedAliasDigest aliasDigest: String,
        uncheckedPurgeCompleted purgeCompleted: Bool
    ) {
        self.profileID = profileID
        self.deletedAt = deletedAt
        self.deletionRevision = deletionRevision
        self.aliasDigest = aliasDigest
        self.purgeCompleted = purgeCompleted
    }
}
