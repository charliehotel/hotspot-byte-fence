import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class PersistenceCrossFileTests: XCTestCase {
    func testInstallationMarkerIsCommittedAfterCanonicalAndLKG() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "complete")
        let digest = try StoreJSONCodec.sha256Hex(StoreJSONCodec.encode(document))
        let marker = try InstallationMarkerV1(
            installationID: store.installationID,
            hasCompletedProfile: true,
            firstCompletedStoreRevision: document.storeRevision,
            firstCompletedStoreDigest: digest,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        try store.commitFirstCompletedProfile(document, marker: marker)

        XCTAssertEqual(try store.load(), .loaded(document))
        XCTAssertEqual(
            try StoreJSONCodec.decode(InstallationMarkerV1.self, from: Data(contentsOf: store.paths.installationURL)),
            marker
        )
        let journal = try StoreJSONCodec.decode(
            CommitJournalV1.self,
            from: Data(contentsOf: store.paths.journalURL)
        )
        XCTAssertEqual(journal.operation, .firstCompletedProfile)
        XCTAssertEqual(journal.phase, .complete)
        XCTAssertNotNil(journal.installationDigest)
    }

    func testTombstoneSetUsesSortedArrayAndRejectsDuplicateProfiles() throws {
        let first = try tombstone(profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let second = try tombstone(profileID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let set = try TombstoneSetV1(records: [first, second])
        let data = try StoreJSONCodec.encode(set)

        XCTAssertEqual(set.records.map(\.profileID), [second.profileID, first.profileID])
        XCTAssertEqual(data.first, UInt8(ascii: "["))
        XCTAssertEqual(try TombstoneSetV1(records: [first, second]), set)
        XCTAssertThrowsError(try TombstoneSetV1(records: [first, first])) { error in
            XCTAssertEqual(error as? PersistenceError, .duplicateTombstone)
        }
        let mixedState = try TombstoneRecord(
            profileID: second.profileID,
            deletedAt: second.deletedAt,
            deletionRevision: second.deletionRevision,
            aliasDigest: second.aliasDigest,
            purgeCompleted: true
        )
        XCTAssertThrowsError(try TombstoneSetV1(records: [first, mixedState])) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidTombstoneState)
        }
    }

    func testProfileDeletionCommitsCompletedTombstonesWithCanonicalAndLKG() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        try store.commit(
            TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "before-delete"),
            operation: .measurementSample
        )
        let pending = try TombstoneSetV1(records: [try tombstone()])
        let deletedDocument = TestDocument(storeRevision: DecimalUInt64(rawValue: 2), value: "after-delete")

        try store.commitProfileDeletion(deletedDocument, tombstones: pending)

        XCTAssertEqual(try store.load(), .loaded(deletedDocument))
        let persisted = try StoreJSONCodec.decode(
            TombstoneSetV1.self,
            from: Data(contentsOf: store.paths.tombstonesURL)
        )
        XCTAssertTrue(persisted.records.allSatisfy(\.purgeCompleted))
        XCTAssertFalse(persisted.isPurgePending)
        XCTAssertTrue(persisted.isPurgeCompleted)
        XCTAssertEqual(try fileMode(store.paths.canonicalURL), 0o600)
        XCTAssertEqual(try fileMode(store.paths.lkgURL), 0o600)
        XCTAssertEqual(try fileMode(store.paths.tombstonesURL), 0o600)
        XCTAssertEqual(try fileMode(store.paths.journalURL), 0o600)
        let journal = try StoreJSONCodec.decode(
            CommitJournalV1.self,
            from: Data(contentsOf: store.paths.journalURL)
        )
        XCTAssertEqual(
            try StoreJSONCodec.decode(
                TestDocument.self,
                from: Data(contentsOf: store.paths.canonicalURL)
            ),
            deletedDocument
        )
        XCTAssertEqual(
            try StoreJSONCodec.decode(
                TestDocument.self,
                from: Data(contentsOf: store.paths.lkgURL)
            ),
            deletedDocument
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.paths.installationURL.path))
        XCTAssertEqual(try fileMode(directory), 0o700)
        XCTAssertEqual(journal.installationID, store.installationID)
        XCTAssertEqual(journal.schemaVersion, 1)
        XCTAssertEqual(journal.targetStoreRevision, deletedDocument.storeRevision)
        XCTAssertEqual(
            journal.canonicalDigest,
            try StoreJSONCodec.sha256Hex(Data(contentsOf: store.paths.canonicalURL))
        )
        XCTAssertEqual(
            journal.lkgDigest,
            try StoreJSONCodec.sha256Hex(Data(contentsOf: store.paths.lkgURL))
        )
        XCTAssertEqual(journal.tombstoneDigest, try persisted.canonicalDigest())
        XCTAssertEqual(
            journal.tombstoneDigest,
            try? StoreJSONCodec.sha256Hex(Data(contentsOf: store.paths.tombstonesURL))
        )
        XCTAssertEqual(journal.operation, .profileDeletion)
        XCTAssertEqual(journal.phase, .complete)
        XCTAssertNotNil(journal.tombstoneDigest)
    }

    func testIncompleteDeletionRequiresExplicitRecovery() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let original = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "before-delete")
        try store.commit(original, operation: .measurementSample)
        let pending = try TombstoneSetV1(records: [try tombstone()])
        try StoreJSONCodec.write(pending, to: store.paths.tombstonesURL)
        let journal = CommitJournalV1(
            installationID: store.installationID,
            operation: .profileDeletion,
            targetStoreRevision: DecimalUInt64(rawValue: 2),
            phase: .purgeInProgress,
            canonicalDigest: try StoreJSONCodec.sha256Hex(Data(contentsOf: store.paths.canonicalURL)),
            lkgDigest: try StoreJSONCodec.sha256Hex(Data(contentsOf: store.paths.lkgURL)),
            tombstoneDigest: try pending.canonicalDigest()
        )
        try StoreJSONCodec.write(journal, to: store.paths.journalURL)
        let recovered = TestDocument(storeRevision: DecimalUInt64(rawValue: 2), value: "after-delete")

        XCTAssertEqual(try store.load(), .recoveryRequired(.incompleteJournal))
        try store.recoverProfileDeletion(recovered, tombstones: pending)
        XCTAssertEqual(try store.load(), .loaded(recovered))
    }

    func testInstallationMarkerDigestMismatchRequiresRecovery() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "complete")
        let marker = try marker(for: document, installationID: store.installationID)
        try store.commitFirstCompletedProfile(document, marker: marker)
        let tampered = try InstallationMarkerV1(
            installationID: marker.installationID,
            hasCompletedProfile: true,
            firstCompletedStoreRevision: marker.firstCompletedStoreRevision,
            firstCompletedStoreDigest: String(repeating: "0", count: 64),
            createdAt: marker.createdAt,
            updatedAt: marker.updatedAt
        )
        try StoreJSONCodec.write(tampered, to: store.paths.installationURL)

        XCTAssertEqual(try store.load(), .recoveryRequired(.integrityFailure))
    }

    func testCompletedDeletionTombstoneDigestMismatchRequiresRecovery() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        try store.commit(
            TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "before-delete"),
            operation: .measurementSample
        )
        let pending = try TombstoneSetV1(records: [try tombstone()])
        let deletedDocument = TestDocument(storeRevision: DecimalUInt64(rawValue: 2), value: "after-delete")
        try store.commitProfileDeletion(deletedDocument, tombstones: pending)
        let original = pending.records[0]
        let tampered = try TombstoneSetV1(records: [try TombstoneRecord(
            profileID: original.profileID,
            deletedAt: original.deletedAt,
            deletionRevision: original.deletionRevision,
            aliasDigest: String(repeating: "b", count: 64),
            purgeCompleted: true
        )])
        try StoreJSONCodec.write(tampered, to: store.paths.tombstonesURL)

        XCTAssertEqual(try store.load(), .recoveryRequired(.integrityFailure))
    }

    private func marker(for document: TestDocument, installationID: UUID) throws -> InstallationMarkerV1 {
        try InstallationMarkerV1(
            installationID: installationID,
            hasCompletedProfile: true,
            firstCompletedStoreRevision: document.storeRevision,
            firstCompletedStoreDigest: try StoreJSONCodec.sha256Hex(StoreJSONCodec.encode(document)),
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func tombstone(
        profileID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    ) throws -> TombstoneRecord {
        try TombstoneRecord(
            profileID: profileID,
            deletedAt: Date(timeIntervalSince1970: 1),
            deletionRevision: DecimalUInt64(rawValue: 2),
            aliasDigest: String(repeating: "a", count: 64),
            purgeCompleted: false
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hbf-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fileMode(_ url: URL) throws -> UInt16 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? UInt16)
    }
}

private struct TestDocument: VersionedDocument {
    let storeRevision: DecimalUInt64
    let value: String
}
