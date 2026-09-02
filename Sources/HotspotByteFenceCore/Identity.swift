import Foundation

public enum IdentityError: Error, Equatable {
    case invalidSSIDLength
    case invalidHex
    case invalidBSSID
    case emptyAlias
    case emptyInterfaceName
    case emptyBSSIDSet
}

public struct SSID: Codable, Equatable, Hashable, Sendable {
    public let bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard (1...32).contains(bytes.count) else {
            throw IdentityError.invalidSSIDLength
        }
        self.bytes = bytes
    }

    public init(hex: String) throws {
        try self.init(bytes: IdentityHexCodec.parse(hex, exactOctetCount: nil))
    }

    public var hex: String {
        IdentityHexCodec.encode(bytes)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(hex: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

public struct BSSID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init(string: String) throws {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({ $0.count == 2 }) else {
            throw IdentityError.invalidBSSID
        }
        var parsed: [UInt8] = []
        for part in parts {
            guard let value = try IdentityHexCodec.parse(String(part), exactOctetCount: 1).first else {
                throw IdentityError.invalidBSSID
            }
            parsed.append(value)
        }
        self.bytes = parsed
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count == 6 else {
            throw IdentityError.invalidBSSID
        }
        self.bytes = bytes
    }

    public var description: String {
        bytes.map { IdentityHexCodec.encode([$0]) }.joined(separator: ":")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(string: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

public struct ProfileAlias: Codable, Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty else {
            throw IdentityError.emptyAlias
        }
        self.value = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct ProfileID: Codable, Equatable, Hashable, Sendable {
    public let value: UUID

    public init(_ value: UUID = UUID()) {
        self.value = value
    }
}

public struct NetworkIdentity: Codable, Equatable, Sendable {
    public let ssid: SSID
    public let interfaceName: String
    public let confirmedBSSIDs: [BSSID]

    public init(ssid: SSID, interfaceName: String, confirmedBSSIDs: [BSSID]) throws {
        guard !interfaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IdentityError.emptyInterfaceName
        }
        guard !confirmedBSSIDs.isEmpty else {
            throw IdentityError.emptyBSSIDSet
        }
        self.ssid = ssid
        self.interfaceName = interfaceName
        self.confirmedBSSIDs = confirmedBSSIDs.reduce(into: []) { result, bssid in
            if !result.contains(bssid) {
                result.append(bssid)
            }
        }.sorted { $0.description < $1.description }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ssid: container.decode(SSID.self, forKey: .ssid),
            interfaceName: container.decode(String.self, forKey: .interfaceName),
            confirmedBSSIDs: container.decode([BSSID].self, forKey: .confirmedBSSIDs)
        )
    }

    public func matchesInterfaceAndSSID(_ snapshot: WiFiIdentitySnapshot) -> Bool {
        snapshot.interfaceName == interfaceName && snapshot.ssid == ssid
    }

    public func matchesExact(_ snapshot: WiFiIdentitySnapshot) -> Bool {
        matchesInterfaceAndSSID(snapshot) && confirmedBSSIDs.contains(snapshot.bssid)
    }

    private enum CodingKeys: String, CodingKey {
        case ssid
        case interfaceName
        case confirmedBSSIDs
    }
}

public struct ProfileDefinition: Codable, Equatable, Sendable {
    public let id: ProfileID
    public let alias: ProfileAlias
    public let identity: NetworkIdentity

    public init(id: ProfileID, alias: ProfileAlias, identity: NetworkIdentity) {
        self.id = id
        self.alias = alias
        self.identity = identity
    }
}

public enum WiFiLinkState: String, Codable, Equatable, Sendable {
    case associated
    case notAssociated
}

public struct WiFiIdentitySnapshot: Codable, Equatable, Sendable {
    public let interfaceName: String
    public let interfaceIndex: UInt32
    public let linkState: WiFiLinkState
    public let ssid: SSID
    public let bssid: BSSID

    public init(
        interfaceName: String,
        interfaceIndex: UInt32,
        linkState: WiFiLinkState,
        ssid: SSID,
        bssid: BSSID
    ) {
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.linkState = linkState
        self.ssid = ssid
        self.bssid = bssid
    }
}

public enum StableIdentityError: Error, Equatable {
    case inconsistentReads
}

public enum StableIdentitySnapshot {
    public static func requireEqual(
        _ first: WiFiIdentitySnapshot,
        _ second: WiFiIdentitySnapshot
    ) throws -> WiFiIdentitySnapshot {
        guard first == second else {
            throw StableIdentityError.inconsistentReads
        }
        return first
    }
}
