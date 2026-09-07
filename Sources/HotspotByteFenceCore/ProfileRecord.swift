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
    public let limitBytes: ByteCount
    public let resetDay: UInt
    public let cycle: CycleRecord
    public let measurement: MeasurementRecord
    public let protection: ProtectionRecord
    public let createdAt: Date
    public let updatedAt: Date

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
        guard ProfileRecord.minimumLimitBytes...ProfileRecord.maximumLimitBytes ~= limitBytes.rawValue else {
            throw ProfileRecordValidationError.invalidLimit
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
        self.limitBytes = limitBytes
        self.resetDay = resetDay
        self.cycle = cycle
        self.measurement = measurement
        self.protection = protection
       self.createdAt = createdAt
       self.updatedAt = updatedAt
   }

    public func updating(
        aliasNFC: String? = nil,
        limitBytes: ByteCount? = nil,
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
            limitBytes: limitBytes ?? self.limitBytes,
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
        try self.init(
            profileID: container.decode(UUID.self, forKey: .profileID),
            aliasNFC: container.decode(String.self, forKey: .aliasNFC),
            ssidHex: container.decodeIfPresent(String.self, forKey: .ssidHex),
            interfaceName: container.decodeIfPresent(String.self, forKey: .interfaceName),
            confirmedBSSIDs: container.decode([BSSID].self, forKey: .confirmedBSSIDs),
            isComplete: container.decode(Bool.self, forKey: .isComplete),
            sharesInterfaceSSID: container.decode(Bool.self, forKey: .sharesInterfaceSSID),
            limitBytes: container.decode(ByteCount.self, forKey: .limitBytes),
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
        try container.encode(limitBytes, forKey: .limitBytes)
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
        case limitBytes
        case resetDay
        case cycle
        case measurement
        case protection
        case createdAt
        case updatedAt
    }
}
