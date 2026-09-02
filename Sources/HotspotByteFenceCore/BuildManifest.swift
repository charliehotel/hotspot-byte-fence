import Foundation

public enum CompiledMode: String, Codable, Equatable, Sendable {
    case strongBlockingCapable
    case measurementOnly
}

public struct BuildManifestV1: Codable, Equatable, Sendable {
    public static let bundleIdentifier = "com.copylawbot.hotspotbytefence"
    public static let architecture = "arm64"
    public static let minimumOS = "13.0"
    public static let counterSourceID = "netRTInterfaceList2-ifData64-v1"
    public static let strongObservationRequirement = "eventBacked-30s-awake-v1"

    public let schemaVersion: UInt
    public let bundleIdentifier: String
    public let applicationVersion: String
    public let sourceRevision: String?
    public let compiledMode: CompiledMode
    public let architecture: String
    public let minimumOS: String
    public let counterSourceID: String
    public let strongObservationRequirement: String

    public init(
        applicationVersion: String,
        sourceRevision: String?,
        compiledMode: CompiledMode
    ) {
        self.schemaVersion = 1
        self.bundleIdentifier = Self.bundleIdentifier
        self.applicationVersion = applicationVersion
        self.sourceRevision = sourceRevision
        self.compiledMode = compiledMode
        self.architecture = Self.architecture
        self.minimumOS = Self.minimumOS
        self.counterSourceID = Self.counterSourceID
        self.strongObservationRequirement = Self.strongObservationRequirement
    }
}

public enum BuildManifestError: Error, Equatable {
    case schemaVersionMismatch
    case bundleIdentifierMismatch
    case architectureMismatch
    case minimumOSMismatch
    case counterSourceMismatch
    case observationRequirementMismatch
    case compiledModeMismatch
}

public enum BuildConfiguration {
    public static let compiledMode: CompiledMode = .measurementOnly
    public static let manifest = BuildManifestV1(
        applicationVersion: "0.1.0-dev",
        sourceRevision: nil,
        compiledMode: compiledMode
    )

    public static func validate(_ manifest: BuildManifestV1) throws {
        guard manifest.schemaVersion == 1 else {
            throw BuildManifestError.schemaVersionMismatch
        }
        guard manifest.bundleIdentifier == BuildManifestV1.bundleIdentifier else {
            throw BuildManifestError.bundleIdentifierMismatch
        }
        guard manifest.architecture == BuildManifestV1.architecture else {
            throw BuildManifestError.architectureMismatch
        }
        guard manifest.minimumOS == BuildManifestV1.minimumOS else {
            throw BuildManifestError.minimumOSMismatch
        }
        guard manifest.counterSourceID == BuildManifestV1.counterSourceID else {
            throw BuildManifestError.counterSourceMismatch
        }
        guard manifest.strongObservationRequirement == BuildManifestV1.strongObservationRequirement else {
            throw BuildManifestError.observationRequirementMismatch
        }
        guard manifest.compiledMode == compiledMode else {
            throw BuildManifestError.compiledModeMismatch
        }
    }

    public static func canonicalJSON(_ manifest: BuildManifestV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }
}
