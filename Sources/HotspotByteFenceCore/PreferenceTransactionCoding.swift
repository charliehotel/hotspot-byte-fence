import Foundation

extension PreferenceTransactionRecord {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(targetScope, forKey: .targetScope)
        try container.encode(phase, forKey: .phase)
        try container.encode(observation, forKey: .observation)
        try container.encode(observationSource, forKey: .observationSource)
        try container.encode(archiveSchemaVersion, forKey: .archiveSchemaVersion)
        try container.encode(fingerprintAlgorithm, forKey: .fingerprintAlgorithm)
        try container.encode(originalArchive, forKey: .originalArchive)
        try container.encode(originalFingerprint, forKey: .originalFingerprint)
        try container.encode(intendedArchive, forKey: .intendedArchive)
        try container.encode(intendedFingerprint, forKey: .intendedFingerprint)
        try encode(lastWrittenArchive, in: &container, forKey: .lastWrittenArchive)
        try encode(lastWrittenFingerprint, in: &container, forKey: .lastWrittenFingerprint)
        try container.encode(preparedAt, forKey: .preparedAt)
        try encode(appliedAt, in: &container, forKey: .appliedAt)
        try encode(restoredAt, in: &container, forKey: .restoredAt)
        try encode(lastError, in: &container, forKey: .lastError)
    }

    private func encode<Value: Encodable>(
        _ value: Value?,
        in container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }
}
