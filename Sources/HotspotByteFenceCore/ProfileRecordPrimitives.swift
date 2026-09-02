import Foundation

public enum ProfileRecordValidationError: Error, Equatable, Sendable {
    case invalidAlias
    case invalidIdentity
    case invalidCompletion
    case invalidLimit
    case invalidResetDay
    case invalidCycle
    case invalidMeasurementState
    case invalidObservation
    case invalidRetryState
    case invalidDates
}

enum PersistenceDateValidation {
    static func isCanonicalDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let utc = TimeZone(secondsFromGMT: 0) else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard calendar.date(from: DateComponents(year: year, month: month, day: day)) != nil else {
            return false
        }
        return String(format: "%04d-%02d-%02d", year, month, day) == value
    }
}

public struct CycleRecord: Codable, Equatable, Sendable {
    public let trustedCycleDate: String
    public let cycleStartInstant: Date
    public let timeZoneID: String
    public let lastTrustedWallClock: Date
    public let timeAcknowledgementRequired: Bool

    public init(
        trustedCycleDate: String,
        cycleStartInstant: Date,
        timeZoneID: String,
        lastTrustedWallClock: Date,
        timeAcknowledgementRequired: Bool
    ) throws {
        guard PersistenceDateValidation.isCanonicalDate(trustedCycleDate),
              TimeZone(identifier: timeZoneID) != nil,
              cycleStartInstant <= lastTrustedWallClock else {
            throw ProfileRecordValidationError.invalidCycle
        }
        self.trustedCycleDate = trustedCycleDate
        self.cycleStartInstant = cycleStartInstant
        self.timeZoneID = timeZoneID
        self.lastTrustedWallClock = lastTrustedWallClock
        self.timeAcknowledgementRequired = timeAcknowledgementRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            trustedCycleDate: container.decode(String.self, forKey: .trustedCycleDate),
            cycleStartInstant: container.decode(Date.self, forKey: .cycleStartInstant),
            timeZoneID: container.decode(String.self, forKey: .timeZoneID),
            lastTrustedWallClock: container.decode(Date.self, forKey: .lastTrustedWallClock),
            timeAcknowledgementRequired: container.decode(
                Bool.self,
                forKey: .timeAcknowledgementRequired
            )
        )
    }

    private enum CodingKeys: String, CodingKey {
        case trustedCycleDate
        case cycleStartInstant
        case timeZoneID
        case lastTrustedWallClock
        case timeAcknowledgementRequired
    }
}

public struct IdentitySnapshotRecord: Codable, Equatable, Sendable {
    public let profileID: UUID
    public let interfaceName: String
    public let interfaceIndex: UInt32
    public let linkState: WiFiLinkState
    public let ssidHex: String
    public let bssid: String

    public init(
        profileID: UUID,
        interfaceName: String,
        interfaceIndex: UInt32,
        linkState: WiFiLinkState,
        ssidHex: String,
        bssid: String
    ) throws {
        let trimmedInterface = interfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard interfaceIndex > 0,
              !trimmedInterface.isEmpty,
              trimmedInterface == interfaceName,
              linkState == .associated,
              let ssid = try? SSID(hex: ssidHex),
              ssid.hex == ssidHex,
              let parsedBSSID = try? BSSID(string: bssid),
              parsedBSSID.description == bssid else {
            throw ProfileRecordValidationError.invalidIdentity
        }
        self.profileID = profileID
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.linkState = linkState
        self.ssidHex = ssidHex
        self.bssid = bssid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            profileID: container.decode(UUID.self, forKey: .profileID),
            interfaceName: container.decode(String.self, forKey: .interfaceName),
            interfaceIndex: container.decode(UInt32.self, forKey: .interfaceIndex),
            linkState: container.decode(WiFiLinkState.self, forKey: .linkState),
            ssidHex: container.decode(String.self, forKey: .ssidHex),
            bssid: container.decode(String.self, forKey: .bssid)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileID
        case interfaceName
        case interfaceIndex
        case linkState
        case ssidHex
        case bssid
    }
}
