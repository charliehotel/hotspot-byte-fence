import Foundation

public enum DistributionSourceV1: String, Codable, Equatable, Sendable {
    case githubRelease
}

public enum CodeSignatureStatusV1: String, Codable, Equatable, Sendable {
    case unsigned
    case adhoc
    case developerID
}

public enum HardenedRuntimeStatusV1: String, Codable, Equatable, Sendable {
    case unavailable
    case enabled
    case disabled
}

public enum NotarizationStatusV1: String, Codable, Equatable, Sendable {
    case notApplicable
    case notarized
    case failed
    case unknown
}

public enum GatekeeperStatusV1: String, Codable, Equatable, Sendable {
    case allowed
    case userApproved
    case blocked
    case notApplicable
}

public enum QuarantineStatusV1: String, Codable, Equatable, Sendable {
    case present
    case removed
    case absent
    case unknown
}

public enum ArtifactObservationRecordValidationError: Error, Equatable, Sendable {
    case invalidSchemaVersion
    case invalidDigest
    case invalidReleaseManifestBinding
    case invalidSignatureState
    case invalidString
    case invalidDate
    case missingNullableField
}

public struct ArtifactObservationRecord: Codable, Equatable, Sendable {
    public let buildManifestSchemaVersion: UInt
    public let compiledModeObserved: CompiledMode
    public let buildManifestSHA256: String
    public let sourceRevision: String?
    public let distributionSource: DistributionSourceV1
    public let releaseManifestID: String?
    public let releaseManifestSHA256: String?
    public let releaseAssetSHA256: String?
    public let appBundleSHA256: String?
    public let executableSHA256: String?
    public let codeSignatureStatus: CodeSignatureStatusV1
    public let codeSignatureTeamID: String?
    public let hardenedRuntimeStatus: HardenedRuntimeStatusV1
    public let notarizationStatus: NotarizationStatusV1
    public let gatekeeperStatus: GatekeeperStatusV1
    public let quarantineStatus: QuarantineStatusV1
    public let architecture: String
    public let macOSBuild: String
    public let observedAt: Date

    public init(
        buildManifestSchemaVersion: UInt = 1,
        compiledModeObserved: CompiledMode,
        buildManifestSHA256: String,
        sourceRevision: String? = nil,
        distributionSource: DistributionSourceV1 = .githubRelease,
        releaseManifestID: String? = nil,
        releaseManifestSHA256: String? = nil,
        releaseAssetSHA256: String? = nil,
        appBundleSHA256: String? = nil,
        executableSHA256: String? = nil,
        codeSignatureStatus: CodeSignatureStatusV1,
        codeSignatureTeamID: String? = nil,
        hardenedRuntimeStatus: HardenedRuntimeStatusV1,
        notarizationStatus: NotarizationStatusV1,
        gatekeeperStatus: GatekeeperStatusV1,
        quarantineStatus: QuarantineStatusV1,
        architecture: String = BuildManifestV1.architecture,
        macOSBuild: String,
        observedAt: Date
    ) throws {
        self.buildManifestSchemaVersion = buildManifestSchemaVersion
        self.compiledModeObserved = compiledModeObserved
        self.buildManifestSHA256 = buildManifestSHA256
        self.sourceRevision = sourceRevision
        self.distributionSource = distributionSource
        self.releaseManifestID = releaseManifestID
        self.releaseManifestSHA256 = releaseManifestSHA256
        self.releaseAssetSHA256 = releaseAssetSHA256
        self.appBundleSHA256 = appBundleSHA256
        self.executableSHA256 = executableSHA256
        self.codeSignatureStatus = codeSignatureStatus
        self.codeSignatureTeamID = codeSignatureTeamID
        self.hardenedRuntimeStatus = hardenedRuntimeStatus
        self.notarizationStatus = notarizationStatus
        self.gatekeeperStatus = gatekeeperStatus
        self.quarantineStatus = quarantineStatus
        self.architecture = architecture
        self.macOSBuild = macOSBuild
        self.observedAt = observedAt
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.sourceRevision),
              container.contains(.releaseManifestID),
              container.contains(.releaseManifestSHA256),
              container.contains(.releaseAssetSHA256),
              container.contains(.appBundleSHA256),
              container.contains(.executableSHA256),
              container.contains(.codeSignatureTeamID) else {
            throw ArtifactObservationRecordValidationError.missingNullableField
        }
        try self.init(
            buildManifestSchemaVersion: container.decode(UInt.self, forKey: .buildManifestSchemaVersion),
            compiledModeObserved: container.decode(CompiledMode.self, forKey: .compiledModeObserved),
            buildManifestSHA256: container.decode(String.self, forKey: .buildManifestSHA256),
            sourceRevision: container.decodeIfPresent(String.self, forKey: .sourceRevision),
            distributionSource: container.decode(DistributionSourceV1.self, forKey: .distributionSource),
            releaseManifestID: container.decodeIfPresent(String.self, forKey: .releaseManifestID),
            releaseManifestSHA256: container.decodeIfPresent(String.self, forKey: .releaseManifestSHA256),
            releaseAssetSHA256: container.decodeIfPresent(String.self, forKey: .releaseAssetSHA256),
            appBundleSHA256: container.decodeIfPresent(String.self, forKey: .appBundleSHA256),
            executableSHA256: container.decodeIfPresent(String.self, forKey: .executableSHA256),
            codeSignatureStatus: container.decode(CodeSignatureStatusV1.self, forKey: .codeSignatureStatus),
            codeSignatureTeamID: container.decodeIfPresent(String.self, forKey: .codeSignatureTeamID),
            hardenedRuntimeStatus: container.decode(HardenedRuntimeStatusV1.self, forKey: .hardenedRuntimeStatus),
            notarizationStatus: container.decode(NotarizationStatusV1.self, forKey: .notarizationStatus),
            gatekeeperStatus: container.decode(GatekeeperStatusV1.self, forKey: .gatekeeperStatus),
            quarantineStatus: container.decode(QuarantineStatusV1.self, forKey: .quarantineStatus),
            architecture: container.decode(String.self, forKey: .architecture),
            macOSBuild: container.decode(String.self, forKey: .macOSBuild),
            observedAt: container.decode(Date.self, forKey: .observedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appBundleSHA256, forKey: .appBundleSHA256)
        try container.encode(architecture, forKey: .architecture)
        try container.encode(buildManifestSHA256, forKey: .buildManifestSHA256)
        try container.encode(buildManifestSchemaVersion, forKey: .buildManifestSchemaVersion)
        try container.encode(codeSignatureStatus, forKey: .codeSignatureStatus)
        try encodeExplicitOptional(codeSignatureTeamID, in: &container, forKey: .codeSignatureTeamID)
        try container.encode(compiledModeObserved, forKey: .compiledModeObserved)
        try container.encode(distributionSource, forKey: .distributionSource)
        try encodeExplicitOptional(executableSHA256, in: &container, forKey: .executableSHA256)
        try container.encode(gatekeeperStatus, forKey: .gatekeeperStatus)
        try container.encode(hardenedRuntimeStatus, forKey: .hardenedRuntimeStatus)
        try container.encode(macOSBuild, forKey: .macOSBuild)
        try container.encode(notarizationStatus, forKey: .notarizationStatus)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(quarantineStatus, forKey: .quarantineStatus)
        try encodeExplicitOptional(releaseAssetSHA256, in: &container, forKey: .releaseAssetSHA256)
        try encodeExplicitOptional(releaseManifestID, in: &container, forKey: .releaseManifestID)
        try encodeExplicitOptional(releaseManifestSHA256, in: &container, forKey: .releaseManifestSHA256)
        try encodeExplicitOptional(sourceRevision, in: &container, forKey: .sourceRevision)
    }

    private func validate() throws {
        guard buildManifestSchemaVersion == 1 else {
            throw ArtifactObservationRecordValidationError.invalidSchemaVersion
        }
        guard PersistenceDigest.isValid(buildManifestSHA256) else {
            throw ArtifactObservationRecordValidationError.invalidDigest
        }
        if releaseManifestID != nil {
            guard let releaseManifestSHA256,
                  let releaseAssetSHA256,
                  let appBundleSHA256,
                  let executableSHA256,
                  PersistenceDigest.isValid(releaseManifestSHA256),
                  PersistenceDigest.isValid(releaseAssetSHA256),
                  PersistenceDigest.isValid(appBundleSHA256),
                  PersistenceDigest.isValid(executableSHA256) else {
                throw ArtifactObservationRecordValidationError.invalidReleaseManifestBinding
            }
        } else {
            guard releaseManifestSHA256 == nil, releaseAssetSHA256 == nil else {
                throw ArtifactObservationRecordValidationError.invalidReleaseManifestBinding
            }
            if let appBundleSHA256 {
                guard PersistenceDigest.isValid(appBundleSHA256) else {
                    throw ArtifactObservationRecordValidationError.invalidDigest
                }
            }
            if let executableSHA256 {
                guard PersistenceDigest.isValid(executableSHA256) else {
                    throw ArtifactObservationRecordValidationError.invalidDigest
                }
            }
        }
        switch codeSignatureStatus {
        case .unsigned:
            guard hardenedRuntimeStatus == .unavailable, codeSignatureTeamID == nil else {
                throw ArtifactObservationRecordValidationError.invalidSignatureState
            }
        case .adhoc:
            guard codeSignatureTeamID == nil else {
                throw ArtifactObservationRecordValidationError.invalidSignatureState
            }
        case .developerID:
            break
        }
        guard !architecture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !macOSBuild.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ArtifactObservationRecordValidationError.invalidString
        }
        guard observedAt.timeIntervalSince1970.isFinite else {
            throw ArtifactObservationRecordValidationError.invalidDate
        }
    }

    private enum CodingKeys: String, CodingKey {
        case appBundleSHA256
        case architecture
        case buildManifestSHA256
        case buildManifestSchemaVersion
        case codeSignatureStatus
        case codeSignatureTeamID
        case compiledModeObserved
        case distributionSource
        case executableSHA256
        case gatekeeperStatus
        case hardenedRuntimeStatus
        case macOSBuild
        case notarizationStatus
        case observedAt
        case quarantineStatus
        case releaseAssetSHA256
        case releaseManifestID
        case releaseManifestSHA256
        case sourceRevision
    }
}

