import Foundation

public enum TopologyRoleV1: String, Codable, Equatable, Sendable {
    case t1
    case t2
    case t3
    case t4
}

public enum OperatorValidationResultV1: String, Codable, Equatable, Sendable {
    case valid
    case missingContext
    case staleContext
    case digestMismatch
    case gateOrCaseMismatch
    case unconfirmed
}

public enum OperatorValidationValidationError: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidDigest
    case emptyIdentifier
    case unconfirmed
}

public struct CandidateDigestSetV1: Codable, Equatable, Sendable {
    public let unsignedAssetSHA256: String
    public let appBundleSHA256: String
    public let executableSHA256: String
    public let embeddedManifestSHA256: String

    public init(
        unsignedAssetSHA256: String,
        appBundleSHA256: String,
        executableSHA256: String,
        embeddedManifestSHA256: String
    ) throws {
        guard Self.isValidSHA256(unsignedAssetSHA256),
              Self.isValidSHA256(appBundleSHA256),
              Self.isValidSHA256(executableSHA256),
              Self.isValidSHA256(embeddedManifestSHA256) else {
            throw OperatorValidationValidationError.invalidDigest
        }
        self.unsignedAssetSHA256 = unsignedAssetSHA256
        self.appBundleSHA256 = appBundleSHA256
        self.executableSHA256 = executableSHA256
        self.embeddedManifestSHA256 = embeddedManifestSHA256
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value) || (97...102).contains(scalar.value)
        }
    }
}

public struct OperatorConfirmationRecordV1: Codable, Equatable, Sendable {
    public let confirmedAt: Date
    public let operatorConfirmed: Bool
    public let targetInterfaceName: String
    public let targetSSIDHex: String
    public let targetBSSID: String?
    public let topologyRole: TopologyRoleV1
    public let note: String?

    public init(
        confirmedAt: Date = Date(),
        operatorConfirmed: Bool,
        targetInterfaceName: String,
        targetSSIDHex: String,
        targetBSSID: String? = nil,
        topologyRole: TopologyRoleV1 = .t1,
        note: String? = nil
    ) throws {
        let trimmedInterface = targetInterfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInterface.isEmpty, trimmedInterface == targetInterfaceName else {
            throw OperatorValidationValidationError.emptyIdentifier
        }
        guard let ssid = try? SSID(hex: targetSSIDHex), ssid.hex == targetSSIDHex else {
            throw OperatorValidationValidationError.invalidDigest
        }
        if let targetBSSID {
            _ = try BSSID(string: targetBSSID)
        }
        self.confirmedAt = confirmedAt
        self.operatorConfirmed = operatorConfirmed
        self.targetInterfaceName = targetInterfaceName
        self.targetSSIDHex = targetSSIDHex
        self.targetBSSID = targetBSSID
        self.topologyRole = topologyRole
        self.note = note
    }
}

public struct OperatorValidationContextV1: Codable, Equatable, Sendable {
    public static let schemaVersion: Int = 1

    public let schemaVersion: Int
    public let runID: UUID
    public let digests: CandidateDigestSetV1
    public let gateID: String
    public let caseID: String
    public let operatorConfirmation: OperatorConfirmationRecordV1

    public init(
        runID: UUID,
        digests: CandidateDigestSetV1,
        gateID: String,
        caseID: String,
        operatorConfirmation: OperatorConfirmationRecordV1
    ) throws {
        let trimmedGate = gateID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCase = caseID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGate.isEmpty, !trimmedCase.isEmpty else {
            throw OperatorValidationValidationError.emptyIdentifier
        }
        self.schemaVersion = Self.schemaVersion
        self.runID = runID
        self.digests = digests
        self.gateID = trimmedGate
        self.caseID = trimmedCase
        self.operatorConfirmation = operatorConfirmation
    }
}

public enum OperatorValidationContextValidator {
    public static let maximumConfirmationAgeSeconds: TimeInterval = 300

    public static func validate(
        context: OperatorValidationContextV1?,
        candidateDigests: CandidateDigestSetV1,
        currentGateID: String,
        currentCaseID: String,
        now: Date = Date(),
        maxAgeSeconds: TimeInterval = maximumConfirmationAgeSeconds
    ) -> OperatorValidationResultV1 {
        guard let context else {
            return .missingContext
        }
        guard context.operatorConfirmation.operatorConfirmed else {
            return .unconfirmed
        }
        guard context.digests == candidateDigests else {
            return .digestMismatch
        }
        guard context.gateID == currentGateID && context.caseID == currentCaseID else {
            return .gateOrCaseMismatch
        }
        let age = now.timeIntervalSince(context.operatorConfirmation.confirmedAt)
        if age < -5 || age > maxAgeSeconds {
            return .staleContext
        }
        return .valid
    }
}

