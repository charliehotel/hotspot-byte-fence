import Foundation

public struct MeasurementRecord: Codable, Equatable, Sendable {
    public let usageBytes: ByteCount
    public let baselinePending: Bool
    public let lastTrustedIdentity: IdentitySnapshotRecord?
    public let lastRXBytes: DecimalUInt64?
    public let lastTXBytes: DecimalUInt64?
    public let lastSampleWallClock: Date?
    public let lastPersistedUsageAt: Date
    public let bytesSinceLastFlush: ByteCount

    public init(
        usageBytes: ByteCount,
        baselinePending: Bool,
        lastTrustedIdentity: IdentitySnapshotRecord?,
        lastRXBytes: DecimalUInt64?,
        lastTXBytes: DecimalUInt64?,
        lastSampleWallClock: Date?,
        lastPersistedUsageAt: Date,
        bytesSinceLastFlush: ByteCount
    ) throws {
        let baselineFieldsPresent = [
            lastTrustedIdentity != nil,
            lastRXBytes != nil,
            lastTXBytes != nil,
            lastSampleWallClock != nil
        ].allSatisfy { $0 }
        guard baselineFieldsPresent == !baselinePending else {
            throw ProfileRecordValidationError.invalidMeasurementState
        }
        self.usageBytes = usageBytes
        self.baselinePending = baselinePending
        self.lastTrustedIdentity = lastTrustedIdentity
        self.lastRXBytes = lastRXBytes
        self.lastTXBytes = lastTXBytes
        self.lastSampleWallClock = lastSampleWallClock
       self.lastPersistedUsageAt = lastPersistedUsageAt
       self.bytesSinceLastFlush = bytesSinceLastFlush
   }

    public static func initial(
        usageBytes: ByteCount = ByteCount(0),
        persistedAt: Date = Date()
    ) throws -> MeasurementRecord {
        try MeasurementRecord(
            usageBytes: usageBytes,
            baselinePending: true,
            lastTrustedIdentity: nil,
            lastRXBytes: nil,
            lastTXBytes: nil,
            lastSampleWallClock: nil,
            lastPersistedUsageAt: persistedAt,
            bytesSinceLastFlush: ByteCount(0)
        )
    }

   public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.lastTrustedIdentity),
              container.contains(.lastRXBytes),
              container.contains(.lastTXBytes),
              container.contains(.lastSampleWallClock) else {
            throw ProfileRecordValidationError.invalidMeasurementState
        }
        try self.init(
            usageBytes: container.decode(ByteCount.self, forKey: .usageBytes),
            baselinePending: container.decode(Bool.self, forKey: .baselinePending),
            lastTrustedIdentity: container.decodeIfPresent(
                IdentitySnapshotRecord.self,
                forKey: .lastTrustedIdentity
            ),
            lastRXBytes: container.decodeIfPresent(
                DecimalUInt64.self,
                forKey: .lastRXBytes
            ),
            lastTXBytes: container.decodeIfPresent(
                DecimalUInt64.self,
                forKey: .lastTXBytes
            ),
            lastSampleWallClock: container.decodeIfPresent(
                Date.self,
                forKey: .lastSampleWallClock
            ),
            lastPersistedUsageAt: container.decode(Date.self, forKey: .lastPersistedUsageAt),
            bytesSinceLastFlush: container.decode(ByteCount.self, forKey: .bytesSinceLastFlush)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usageBytes, forKey: .usageBytes)
        try container.encode(baselinePending, forKey: .baselinePending)
        try encodeExplicitOptional(lastTrustedIdentity, in: &container, forKey: .lastTrustedIdentity)
        try encodeExplicitOptional(lastRXBytes, in: &container, forKey: .lastRXBytes)
        try encodeExplicitOptional(lastTXBytes, in: &container, forKey: .lastTXBytes)
        try encodeExplicitOptional(
            lastSampleWallClock,
            in: &container,
            forKey: .lastSampleWallClock
        )
        try container.encode(lastPersistedUsageAt, forKey: .lastPersistedUsageAt)
        try container.encode(bytesSinceLastFlush, forKey: .bytesSinceLastFlush)
    }

    private enum CodingKeys: String, CodingKey {
        case usageBytes
        case baselinePending
        case lastTrustedIdentity
        case lastRXBytes
        case lastTXBytes
        case lastSampleWallClock
        case lastPersistedUsageAt
        case bytesSinceLastFlush
    }
}
