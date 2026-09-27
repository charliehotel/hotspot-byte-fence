import Foundation

public struct ProfileRecord: Codable, Equatable, Sendable {
    public static let minimumLimitBytes: UInt64 = 10_000_000
    public static let maximumLimitBytes: UInt64 = 1_000_000_000_000

    public let profileID: UUID
    public let aliasNFC: String
    public let ssidHex: String?
    public let interfaceName: String?
    public let confirmedBSSIDs: [BSSID]
    public let isComplete: Bool
    public let sharesInterfaceSSID: Bool
    public let quota: QuotaLimit
    public var limitBytes: ByteCount? { quota.finiteBytes }
    public let resetDay: UInt
    public let cycle: CycleRecord
    public let measurement: MeasurementRecord
    public let protection: ProtectionRecord
    public let createdAt: Date
    public let updatedAt: Date

    public var isUnlimited: Bool { quota.isUnlimited }

    public static func hasReachedLimit(usageBytes: ByteCount, quota: QuotaLimit) -> Bool {
        guard let limitBytes = quota.finiteBytes else { return false }
        return usageBytes.rawValue >= limitBytes.rawValue
    }

    public init(
        profileID: UUID,
        aliasNFC: String,
        ssidHex: String?,
        interfaceName: String?,
        confirmedBSSIDs: [BSSID],
        isComplete: Bool,
        sharesInterfaceSSID: Bool,
        quota: QuotaLimit,
        resetDay: UInt,
        cycle: CycleRecord,
        measurement: MeasurementRecord,
        protection: ProtectionRecord,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        let normalizedAlias: String
        do {
            normalizedAlias = try ProfileAlias(aliasNFC).value
        } catch {
            throw ProfileRecordValidationError.invalidAlias
        }

        let hasSSID = ssidHex != nil
        let hasInterface = interfaceName != nil
        guard hasSSID == hasInterface else {
            throw ProfileRecordValidationError.invalidIdentity
        }
        if let ssidHex {
            guard let ssid = try? SSID(hex: ssidHex), ssid.hex == ssidHex else {
                throw ProfileRecordValidationError.invalidIdentity
            }
        }
        if let interfaceName {
            let trimmed = interfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed == interfaceName else {
                throw ProfileRecordValidationError.invalidIdentity
            }
        }
        if !confirmedBSSIDs.isEmpty, !(hasSSID && hasInterface) {
            throw ProfileRecordValidationError.invalidIdentity
        }

        let sortedBSSIDs = Array(Set(confirmedBSSIDs)).sorted { $0.description < $1.description }
        let identityComplete = hasSSID && hasInterface && !sortedBSSIDs.isEmpty
        guard isComplete == identityComplete else {
            throw ProfileRecordValidationError.invalidCompletion
        }
        if case let .finite(limitBytes) = quota {
            guard ProfileRecord.minimumLimitBytes...ProfileRecord.maximumLimitBytes ~= limitBytes.rawValue else {
                throw ProfileRecordValidationError.invalidLimit
            }
        }
        guard (1...31).contains(resetDay) else {
            throw ProfileRecordValidationError.invalidResetDay
        }
        guard updatedAt >= createdAt else {
            throw ProfileRecordValidationError.invalidDates
        }

        self.profileID = profileID
        self.aliasNFC = normalizedAlias
        self.ssidHex = ssidHex
        self.interfaceName = interfaceName
        self.confirmedBSSIDs = sortedBSSIDs
        self.isComplete = isComplete
        self.sharesInterfaceSSID = sharesInterfaceSSID
        self.quota = quota
        self.resetDay = resetDay
        self.cycle = cycle
        self.measurement = measurement
        self.protection = protection
       self.createdAt = createdAt
       self.updatedAt = updatedAt
   }

    public init(
        profileID: UUID,
        aliasNFC: String,
        ssidHex: String?,
        interfaceName: String?,
        confirmedBSSIDs: [BSSID],
        isComplete: Bool,
        sharesInterfaceSSID: Bool,
        limitBytes: ByteCount,
        resetDay: UInt,
        cycle: CycleRecord,
        measurement: MeasurementRecord,
        protection: ProtectionRecord,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        try self.init(
            profileID: profileID,
            aliasNFC: aliasNFC,
            ssidHex: ssidHex,
            interfaceName: interfaceName,
            confirmedBSSIDs: confirmedBSSIDs,
            isComplete: isComplete,
            sharesInterfaceSSID: sharesInterfaceSSID,
            quota: QuotaLimit.fromLegacyLimitBytes(limitBytes),
            resetDay: resetDay,
            cycle: cycle,
            measurement: measurement,
            protection: protection,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func updating(
        aliasNFC: String? = nil,
        limitBytes: ByteCount? = nil,
        quota: QuotaLimit? = nil,
        resetDay: UInt? = nil,
        confirmedBSSIDs: [BSSID]? = nil,
        cycle: CycleRecord? = nil,
        measurement: MeasurementRecord? = nil,
        protection: ProtectionRecord? = nil,
        updatedAt: Date = Date()
    ) throws -> ProfileRecord {
        try ProfileRecord(
            profileID: self.profileID,
            aliasNFC: aliasNFC ?? self.aliasNFC,
            ssidHex: self.ssidHex,
            interfaceName: self.interfaceName,
            confirmedBSSIDs: confirmedBSSIDs ?? self.confirmedBSSIDs,
            isComplete: self.isComplete,
            sharesInterfaceSSID: self.sharesInterfaceSSID,
            quota: quota ?? limitBytes.map(QuotaLimit.fromLegacyLimitBytes) ?? self.quota,
            resetDay: resetDay ?? self.resetDay,
            cycle: cycle ?? self.cycle,
            measurement: measurement ?? self.measurement,
            protection: protection ?? self.protection,
            createdAt: self.createdAt,
            updatedAt: updatedAt
        )
    }

   public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.ssidHex), container.contains(.interfaceName) else {
            throw ProfileRecordValidationError.invalidIdentity
        }
        let quota: QuotaLimit
        if container.contains(.quota) {
            quota = try container.decode(QuotaLimit.self, forKey: .quota)
        } else {
            quota = QuotaLimit.fromLegacyLimitBytes(
                try container.decode(ByteCount.self, forKey: .limitBytes)
            )
        }
        try self.init(
            profileID: container.decode(UUID.self, forKey: .profileID),
            aliasNFC: container.decode(String.self, forKey: .aliasNFC),
            ssidHex: container.decodeIfPresent(String.self, forKey: .ssidHex),
            interfaceName: container.decodeIfPresent(String.self, forKey: .interfaceName),
            confirmedBSSIDs: container.decode([BSSID].self, forKey: .confirmedBSSIDs),
            isComplete: container.decode(Bool.self, forKey: .isComplete),
            sharesInterfaceSSID: container.decode(Bool.self, forKey: .sharesInterfaceSSID),
            quota: quota,
            resetDay: container.decode(UInt.self, forKey: .resetDay),
            cycle: container.decode(CycleRecord.self, forKey: .cycle),
            measurement: container.decode(MeasurementRecord.self, forKey: .measurement),
            protection: container.decode(ProtectionRecord.self, forKey: .protection),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(aliasNFC, forKey: .aliasNFC)
        try encodeExplicitOptional(ssidHex, in: &container, forKey: .ssidHex)
        try encodeExplicitOptional(interfaceName, in: &container, forKey: .interfaceName)
        try container.encode(confirmedBSSIDs, forKey: .confirmedBSSIDs)
        try container.encode(isComplete, forKey: .isComplete)
        try container.encode(sharesInterfaceSSID, forKey: .sharesInterfaceSSID)
        try container.encode(quota, forKey: .quota)
        // Preserve the v0.1.2 field for older app builds during update.
        try container.encode(quota.legacyLimitBytes, forKey: .limitBytes)
        try container.encode(resetDay, forKey: .resetDay)
        try container.encode(cycle, forKey: .cycle)
        try container.encode(measurement, forKey: .measurement)
        try container.encode(protection, forKey: .protection)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case profileID
        case aliasNFC
        case ssidHex
        case interfaceName
        case confirmedBSSIDs
        case isComplete
        case sharesInterfaceSSID
        case quota
        case limitBytes
        case resetDay
        case cycle
        case measurement
        case protection
        case createdAt
        case updatedAt
    }
}
