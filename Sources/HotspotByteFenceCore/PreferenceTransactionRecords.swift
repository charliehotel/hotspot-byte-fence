import Foundation

public enum PreferenceTransactionValidationError: Error, Equatable, Sendable {
    case invalidScope
    case invalidArchiveSchema
    case invalidFingerprintAlgorithm
    case invalidArchive
    case invalidFingerprint
    case invalidState
}

public enum PreferenceTransactionPhaseV1: String, Codable, Equatable, Sendable {
    case prepared
    case applied
    case restorationPending
    case restored
    case conflict
    case unverified
}

public enum PreferenceObservationResultV1: String, Codable, Equatable, Sendable {
    case none
    case pending
    case verified
    case unverified
}

public enum PreferenceObservationSourceV1: String, Codable, Equatable, Sendable {
    case none
    case eventBacked
    case pollBacked
    case lifecycleOnly
}

public enum PreferenceTransactionFailureV1: String, Codable, Equatable, Sendable {
    case preparedWriteOutcomeUnknown
    case externalPreferenceChange
    case readBackUnavailable
    case commitFailed
    case commitReadBackMismatch
    case archiveDecodeFailure
    case archiveNonRepresentable
    case authorizationUnavailable
    case staleTargetIdentity
    case postDisconnectUnverified
    case storeWriteFailure
}

public struct InterfaceSSIDScopeRecord: Codable, Equatable, Sendable {
    public let interfaceName: String
    public let ssidHex: String

    public init(interfaceName: String, ssid: SSID) throws {
        try self.init(interfaceName: interfaceName, ssidHex: ssid.hex)
    }

    public init(interfaceName: String, ssidHex: String) throws {
        let trimmedName = interfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              trimmedName == interfaceName,
              let ssid = try? SSID(hex: ssidHex),
              ssid.hex == ssidHex else {
            throw PreferenceTransactionValidationError.invalidScope
        }
        self.interfaceName = interfaceName
        self.ssidHex = ssidHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            interfaceName: container.decode(String.self, forKey: .interfaceName),
            ssidHex: container.decode(String.self, forKey: .ssidHex)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case interfaceName
        case ssidHex
    }
}

struct PreferenceTransactionStateV1: Equatable, Sendable {
    let phase: PreferenceTransactionPhaseV1
    let observation: PreferenceObservationResultV1
    let observationSource: PreferenceObservationSourceV1
    let lastWrittenArchive: String?
    let lastWrittenFingerprint: String?
    let appliedAt: Date?
    let restoredAt: Date?
    let lastError: PreferenceTransactionFailureV1?
}
