import Foundation

public extension JournaledStateStore {
    func commitFirstCompletedProfile(
        _ document: Document,
        marker: InstallationMarkerV1
    ) throws {
        let canonicalData = try StoreJSONCodec.encode(document)
        let canonicalDigest = StoreJSONCodec.sha256Hex(canonicalData)
        guard marker.hasCompletedProfile,
              marker.installationID == installationID,
              marker.firstCompletedStoreRevision == document.storeRevision,
              marker.firstCompletedStoreDigest == canonicalDigest else {
            throw PersistenceError.validationFailed
        }

        let prepared = CommitJournalV1(
            installationID: installationID,
            operation: .firstCompletedProfile,
            targetStoreRevision: document.storeRevision,
            phase: .prepared,
            canonicalDigest: try digestIfPresent(at: paths.canonicalURL),
            lkgDigest: try digestIfPresent(at: paths.lkgURL),
            installationDigest: try digestIfPresent(at: paths.installationURL)
        )
        try writeJournal(prepared)
        try StoreJSONCodec.writeAtomicallyAndFlush(canonicalData, to: paths.canonicalURL, permissions: 0o600)
        try validateFile(at: paths.canonicalURL, equals: document)
        let canonicalCommitted = try prepared.advancing(
            to: .canonicalCommitted,
            canonicalDigest: try digest(at: paths.canonicalURL)
        )
        try writeJournal(canonicalCommitted)

        try StoreJSONCodec.writeAtomicallyAndFlush(canonicalData, to: paths.lkgURL, permissions: 0o600)
        try validateFile(at: paths.lkgURL, equals: document)
        let lkgCommitted = try canonicalCommitted.advancing(
            to: .lkgCommitted,
            lkgDigest: try digest(at: paths.lkgURL)
        )
        try writeJournal(lkgCommitted)

        try StoreJSONCodec.writeAtomicallyAndFlush(
            try StoreJSONCodec.encode(marker),
            to: paths.installationURL,
            permissions: 0o600
        )
        let persistedMarker: InstallationMarkerV1 = try StoreJSONCodec.decode(
            InstallationMarkerV1.self,
            from: Data(contentsOf: paths.installationURL)
        )
        guard persistedMarker == marker else {
            throw PersistenceError.validationFailed
        }
        let markerCommitted = try lkgCommitted.advancing(
            to: .markerCommitted,
            installationDigest: try digest(at: paths.installationURL)
        )
        try writeJournal(markerCommitted)
        try writeJournal(try markerCommitted.advancing(to: .complete))
    }

    func commitProfileDeletion(
        _ document: Document,
        tombstones: TombstoneSetV1
    ) throws {
        guard tombstones.isPurgePending,
              tombstones.records.allSatisfy({ $0.deletionRevision == document.storeRevision }) else {
            throw PersistenceError.invalidTombstoneState
        }
        let prepared = CommitJournalV1(
            installationID: installationID,
            operation: .profileDeletion,
            targetStoreRevision: document.storeRevision,
            phase: .prepared,
            canonicalDigest: try digestIfPresent(at: paths.canonicalURL),
            lkgDigest: try digestIfPresent(at: paths.lkgURL),
            tombstoneDigest: try digestIfPresent(at: paths.tombstonesURL)
        )
        try writeJournal(prepared)
        try StoreJSONCodec.writeAtomicallyAndFlush(
            try StoreJSONCodec.encode(tombstones),
            to: paths.tombstonesURL,
            permissions: 0o600
        )
        let purgeInProgress = try prepared.advancing(
            to: .purgeInProgress,
            tombstoneDigest: try digest(at: paths.tombstonesURL)
        )
        try writeJournal(purgeInProgress)
        try finishProfileDeletion(document, pending: tombstones, journal: purgeInProgress)
    }

    func recoverProfileDeletion(
        _ document: Document,
        tombstones: TombstoneSetV1
    ) throws {
        guard tombstones.isPurgePending else {
            throw PersistenceError.invalidTombstoneState
        }
        guard let journal = try readJournalIfPresent(),
              journal.installationID == installationID,
              journal.operation == .profileDeletion,
              journal.phase == .purgeInProgress,
              journal.targetStoreRevision == document.storeRevision,
              let currentTombstones: TombstoneSetV1 = try decodeOptionalFile(at: paths.tombstonesURL),
              currentTombstones == tombstones,
              journal.tombstoneDigest == (try? digest(at: paths.tombstonesURL)) else {
            throw PersistenceError.validationFailed
        }
        try finishProfileDeletion(document, pending: tombstones, journal: journal)
    }

    private func finishProfileDeletion(
        _ document: Document,
        pending: TombstoneSetV1,
        journal: CommitJournalV1
    ) throws {
        let canonicalData = try StoreJSONCodec.encode(document)
        try StoreJSONCodec.writeAtomicallyAndFlush(canonicalData, to: paths.canonicalURL, permissions: 0o600)
        try validateFile(at: paths.canonicalURL, equals: document)
        let canonicalRecorded = try journal.recording(canonicalDigest: try digest(at: paths.canonicalURL))
        try writeJournal(canonicalRecorded)

        try StoreJSONCodec.writeAtomicallyAndFlush(canonicalData, to: paths.lkgURL, permissions: 0o600)
        try validateFile(at: paths.lkgURL, equals: document)
        let lkgRecorded = try canonicalRecorded.recording(lkgDigest: try digest(at: paths.lkgURL))
        try writeJournal(lkgRecorded)

        let completed = pending.withPurgeCompleted(true)
        try StoreJSONCodec.writeAtomicallyAndFlush(
            try StoreJSONCodec.encode(completed),
            to: paths.tombstonesURL,
            permissions: 0o600
        )
        let persisted: TombstoneSetV1? = try decodeOptionalFile(at: paths.tombstonesURL)
        guard persisted == completed else {
            throw PersistenceError.validationFailed
        }
        let tombstonesRecorded = try lkgRecorded.recording(
            tombstoneDigest: try digest(at: paths.tombstonesURL)
        )
        try writeJournal(tombstonesRecorded)
        try writeJournal(try tombstonesRecorded.advancing(to: .complete))
    }

    private func decodeOptionalFile<Value: Decodable>(at url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try StoreJSONCodec.decode(Value.self, from: Data(contentsOf: url))
    }
}
