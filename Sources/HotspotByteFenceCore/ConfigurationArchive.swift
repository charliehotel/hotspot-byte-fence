import Foundation

public enum ConfigurationArchiveError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion
    case invalidSSID
    case unsupportedSecurityValue
    case malformedArchive
    case nonCanonicalArchive
    case invalidBase64
}

public struct CWConfigurationArchiveFlagsV1: Codable, Equatable, Sendable {
    public let requireAdministratorForAssociation: Bool
    public let requireAdministratorForIBSSMode: Bool
    public let requireAdministratorForPower: Bool
    public let rememberJoinedNetworks: Bool

    public init(
        requireAdministratorForAssociation: Bool,
        requireAdministratorForIBSSMode: Bool,
        requireAdministratorForPower: Bool,
        rememberJoinedNetworks: Bool
    ) {
        self.requireAdministratorForAssociation = requireAdministratorForAssociation
        self.requireAdministratorForIBSSMode = requireAdministratorForIBSSMode
        self.requireAdministratorForPower = requireAdministratorForPower
        self.rememberJoinedNetworks = rememberJoinedNetworks
    }
}

public struct CWNetworkProfileArchiveV1: Codable, Equatable, Sendable {
    public let ssidHex: String
    public let securityRawValue: DecimalUInt64

    public init(ssid: SSID, securityRawValue: UInt64) throws {
        try self.init(
            ssidHex: ssid.hex,
            securityRawValue: DecimalUInt64(rawValue: securityRawValue)
        )
    }

    public init(ssidHex: String, securityRawValue: DecimalUInt64) throws {
        guard let ssid = try? SSID(hex: ssidHex), ssid.hex == ssidHex else {
            throw ConfigurationArchiveError.invalidSSID
        }
        guard securityRawValue.rawValue <= 15 else {
            throw ConfigurationArchiveError.unsupportedSecurityValue
        }
        self.ssidHex = ssidHex
        self.securityRawValue = securityRawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            ssidHex: container.decode(String.self, forKey: .ssidHex),
            securityRawValue: container.decode(DecimalUInt64.self, forKey: .securityRawValue)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case ssidHex
        case securityRawValue
    }
}

public struct CWConfigurationArchiveV1: Codable, Equatable, Sendable {
    public static let fingerprintAlgorithm = "hbf-cwconfig-v1-sha256"

    public let schemaVersion: UInt
    public let networkProfiles: [CWNetworkProfileArchiveV1]
    public let requireAdministratorForAssociation: Bool
    public let requireAdministratorForIBSSMode: Bool
    public let requireAdministratorForPower: Bool
    public let rememberJoinedNetworks: Bool

    public init(
        networkProfiles: [CWNetworkProfileArchiveV1],
        flags: CWConfigurationArchiveFlagsV1
    ) {
        self.schemaVersion = 1
        self.networkProfiles = networkProfiles
        self.requireAdministratorForAssociation = flags.requireAdministratorForAssociation
        self.requireAdministratorForIBSSMode = flags.requireAdministratorForIBSSMode
        self.requireAdministratorForPower = flags.requireAdministratorForPower
        self.rememberJoinedNetworks = flags.rememberJoinedNetworks
    }

    public init(canonicalData data: Data) throws {
        let decoded: CWConfigurationArchiveV1
        do {
            decoded = try StoreJSONCodec.decode(Self.self, from: data)
        } catch let error as ConfigurationArchiveError {
            throw error
        } catch {
            throw ConfigurationArchiveError.malformedArchive
        }
        guard try StoreJSONCodec.encode(decoded) == data else {
            throw ConfigurationArchiveError.nonCanonicalArchive
        }
        self = decoded
    }

    public init(base64URL: String) throws {
        try self.init(canonicalData: Base64URLCodec.decode(base64URL))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt.self, forKey: .schemaVersion) == 1 else {
            throw ConfigurationArchiveError.unsupportedSchemaVersion
        }
        try self.init(
            networkProfiles: container.decode(
                [CWNetworkProfileArchiveV1].self,
                forKey: .networkProfiles
            ),
            flags: CWConfigurationArchiveFlagsV1(
                requireAdministratorForAssociation: container.decode(
                    Bool.self,
                    forKey: .requireAdministratorForAssociation
                ),
                requireAdministratorForIBSSMode: container.decode(
                    Bool.self,
                    forKey: .requireAdministratorForIBSSMode
                ),
                requireAdministratorForPower: container.decode(
                    Bool.self,
                    forKey: .requireAdministratorForPower
                ),
                rememberJoinedNetworks: container.decode(
                    Bool.self,
                    forKey: .rememberJoinedNetworks
                )
            )
        )
    }

    public var flags: CWConfigurationArchiveFlagsV1 {
        CWConfigurationArchiveFlagsV1(
            requireAdministratorForAssociation: requireAdministratorForAssociation,
            requireAdministratorForIBSSMode: requireAdministratorForIBSSMode,
            requireAdministratorForPower: requireAdministratorForPower,
            rememberJoinedNetworks: rememberJoinedNetworks
        )
    }

    public func removingProfiles(matching ssid: SSID) -> CWConfigurationArchiveV1 {
        CWConfigurationArchiveV1(
            networkProfiles: networkProfiles.filter { $0.ssidHex != ssid.hex },
            flags: flags
        )
    }

    public func canonicalData() throws -> Data {
        try StoreJSONCodec.encode(self)
    }

    public func fingerprint() throws -> String {
        StoreJSONCodec.sha256Hex(try canonicalData())
    }

    public func canonicalBase64URL() throws -> String {
        Base64URLCodec.encode(try canonicalData())
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case networkProfiles
        case requireAdministratorForAssociation
        case requireAdministratorForIBSSMode
        case requireAdministratorForPower
        case rememberJoinedNetworks
    }
}

private enum Base64URLCodec {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) throws -> Data {
        guard value.unicodeScalars.allSatisfy({ scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45, 95:
                true
            default:
                false
            }
        }), !value.contains("="), value.utf8.count % 4 != 1 else {
            throw ConfigurationArchiveError.invalidBase64
        }

        let paddingCount = (4 - (value.utf8.count % 4)) % 4
        let padded = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: paddingCount)
        guard let data = Data(base64Encoded: padded), encode(data) == value else {
            throw ConfigurationArchiveError.invalidBase64
        }
        return data
    }
}
