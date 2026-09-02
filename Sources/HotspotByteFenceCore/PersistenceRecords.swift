import Foundation

public protocol VersionedDocument: Codable, Equatable, Sendable {
    var storeRevision: DecimalUInt64 { get }
}

public struct StorePaths: Equatable, Sendable {
    public let directory: URL
    public let canonicalURL: URL
    public let lkgURL: URL
    public let installationURL: URL
    public let tombstonesURL: URL
    public let journalURL: URL

    public init(directory: URL) {
        let normalizedDirectory = directory.standardizedFileURL
        self.directory = normalizedDirectory
        self.canonicalURL = normalizedDirectory.appendingPathComponent("state.json")
        self.lkgURL = normalizedDirectory.appendingPathComponent("state.lkg.json")
        self.installationURL = normalizedDirectory.appendingPathComponent("installation.json")
        self.tombstonesURL = normalizedDirectory.appendingPathComponent("tombstones.json")
        self.journalURL = normalizedDirectory.appendingPathComponent("commit-journal.json")
    }
}

public enum JournalOperation: String, Codable, Equatable, Sendable {
    case firstCompletedProfile
    case measurementSample
    case limitReached
    case preferencePrepare
    case preferenceApplied
    case restoration
    case profileDeletion
    case recoveryFromLKG

    var usesOnlyCanonicalAndLKG: Bool {
        switch self {
        case .measurementSample, .limitReached, .preferencePrepare, .preferenceApplied, .restoration, .recoveryFromLKG:
            true
        case .firstCompletedProfile, .profileDeletion:
            false
        }
    }
}

public enum JournalPhase: String, Codable, Equatable, Sendable {
    case prepared
    case canonicalCommitted
    case lkgCommitted
    case markerCommitted
    case purgeInProgress
    case complete

    public func canAdvance(to next: JournalPhase) -> Bool {
        switch (self, next) {
        case (.prepared, .canonicalCommitted), (.prepared, .purgeInProgress):
            true
        case (.canonicalCommitted, .lkgCommitted):
            true
        case (.lkgCommitted, .markerCommitted), (.lkgCommitted, .complete):
            true
        case (.markerCommitted, .complete), (.purgeInProgress, .complete):
            true
        default:
            false
        }
    }
}

public struct CommitJournalV1: Codable, Equatable, Sendable {
    public let schemaVersion: UInt
    public let installationID: UUID
    public let operation: JournalOperation
    public let targetStoreRevision: DecimalUInt64
    public let phase: JournalPhase
    public let canonicalDigest: String?
    public let lkgDigest: String?
    public let installationDigest: String?
    public let tombstoneDigest: String?
    public let updatedAt: Date

    public init(
        installationID: UUID,
        operation: JournalOperation,
        targetStoreRevision: DecimalUInt64,
        phase: JournalPhase,
        canonicalDigest: String?,
        lkgDigest: String?,
        installationDigest: String? = nil,
        tombstoneDigest: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = 1
        self.installationID = installationID
        self.operation = operation
        self.targetStoreRevision = targetStoreRevision
        self.phase = phase
        self.canonicalDigest = canonicalDigest
        self.lkgDigest = lkgDigest
        self.installationDigest = installationDigest
        self.tombstoneDigest = tombstoneDigest
        self.updatedAt = updatedAt
    }

    public func advancing(
        to phase: JournalPhase,
        canonicalDigest: String? = nil,
        lkgDigest: String? = nil,
        installationDigest: String? = nil,
        tombstoneDigest: String? = nil,
        updatedAt: Date = Date()
    ) throws -> CommitJournalV1 {
        guard self.phase.canAdvance(to: phase) else {
            throw PersistenceError.invalidPhaseTransition
        }
        return CommitJournalV1(
            installationID: installationID,
            operation: operation,
            targetStoreRevision: targetStoreRevision,
            phase: phase,
            canonicalDigest: canonicalDigest ?? self.canonicalDigest,
            lkgDigest: lkgDigest ?? self.lkgDigest,
            installationDigest: installationDigest ?? self.installationDigest,
            tombstoneDigest: tombstoneDigest ?? self.tombstoneDigest,
            updatedAt: updatedAt
        )
    }

    public func recording(
        canonicalDigest: String? = nil,
        lkgDigest: String? = nil,
        installationDigest: String? = nil,
        tombstoneDigest: String? = nil,
        updatedAt: Date = Date()
    ) throws -> CommitJournalV1 {
        guard phase == .purgeInProgress else {
            throw PersistenceError.invalidPhaseTransition
        }
        return CommitJournalV1(
            installationID: installationID,
            operation: operation,
            targetStoreRevision: targetStoreRevision,
            phase: phase,
            canonicalDigest: canonicalDigest ?? self.canonicalDigest,
            lkgDigest: lkgDigest ?? self.lkgDigest,
            installationDigest: installationDigest ?? self.installationDigest,
            tombstoneDigest: tombstoneDigest ?? self.tombstoneDigest,
            updatedAt: updatedAt
        )
    }
}

public enum PersistenceRecoveryReason: String, Equatable, Sendable {
    case canonicalMissing
    case canonicalDecodeFailure
    case lkgMissing
    case lkgDecodeFailure
    case installationDecodeFailure
    case tombstoneDecodeFailure
    case journalDecodeFailure
    case incompleteJournal
    case integrityFailure
    case permissionModeFailure
}

public enum StoreLoadResult<Document: VersionedDocument>: Equatable {
    case firstRun
    case loaded(Document)
    case recoveryRequired(PersistenceRecoveryReason)
}

public enum PersistenceError: Error, Equatable, Sendable {
    case directoryCreationFailed
    case directoryTypeMismatch
    case fileCreationFailed
    case writeFailed
    case validationFailed
    case invalidDigest
    case duplicateTombstone
    case invalidTombstoneState
    case invalidPhaseTransition
    case unsupportedOperation
}
