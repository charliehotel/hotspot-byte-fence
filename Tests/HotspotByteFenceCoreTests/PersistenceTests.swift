import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class PersistenceTests: XCTestCase {
    func testNewStoreIsFirstRunAndCommitRoundTripsCanonicalAndLKG() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "first")

        XCTAssertEqual(try store.load(), .firstRun)
        try store.commit(document, operation: .measurementSample)

        XCTAssertEqual(try store.load(), .loaded(document))
        XCTAssertEqual(try store.decodeLKG(), document)
        XCTAssertEqual(try fileMode(store.paths.canonicalURL), 0o600)
        XCTAssertEqual(try fileMode(store.paths.lkgURL), 0o600)
        XCTAssertEqual(try fileMode(directory), 0o700)
    }

    func testCorruptCanonicalStateRequiresRecoveryWithoutReplacingIt() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "safe")
        try store.commit(document, operation: .measurementSample)
        try Data("not-json".utf8).write(to: store.paths.canonicalURL)

        XCTAssertEqual(try store.load(), .recoveryRequired(.canonicalDecodeFailure))
        XCTAssertEqual(try Data(contentsOf: store.paths.canonicalURL), Data("not-json".utf8))
        XCTAssertEqual(try store.decodeLKG(), document)
    }

    func testIncompleteJournalBlocksNormalLoadAndAllowsExplicitLKGRecoveryOnly() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "safe")
        try store.commit(document, operation: .measurementSample)
        let journal = CommitJournalV1(
            installationID: store.installationID,
            operation: .measurementSample,
            targetStoreRevision: DecimalUInt64(rawValue: 2),
            phase: .prepared,
            canonicalDigest: nil,
            lkgDigest: nil
        )
        try StoreJSONCodec.write(journal, to: store.paths.journalURL)

        XCTAssertEqual(try store.load(), .recoveryRequired(.incompleteJournal))
        XCTAssertEqual(try store.recoverFromLKG(), document)
        XCTAssertEqual(try store.load(), .loaded(document))
    }

    func testJournalPhaseSequenceRejectsSkippingCanonicalCommit() {
        XCTAssertFalse(JournalPhase.prepared.canAdvance(to: .lkgCommitted))
        XCTAssertTrue(JournalPhase.prepared.canAdvance(to: .canonicalCommitted))
        XCTAssertTrue(JournalPhase.canonicalCommitted.canAdvance(to: .lkgCommitted))
        XCTAssertTrue(JournalPhase.lkgCommitted.canAdvance(to: .complete))
    }

    func testCorruptJournalRequiresRecovery() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "safe")
        try store.commit(document, operation: .measurementSample)
        try Data("not-json".utf8).write(to: store.paths.journalURL)

        XCTAssertEqual(try store.load(), .recoveryRequired(.journalDecodeFailure))
    }

    func testJournalDigestMismatchRequiresRecovery() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "safe")
        try store.commit(document, operation: .measurementSample)
        let journal = try StoreJSONCodec.decode(
            CommitJournalV1.self,
            from: Data(contentsOf: store.paths.journalURL)
        )
        let tampered = CommitJournalV1(
            installationID: journal.installationID,
            operation: journal.operation,
            targetStoreRevision: journal.targetStoreRevision,
            phase: journal.phase,
            canonicalDigest: String(repeating: "0", count: 64),
            lkgDigest: journal.lkgDigest,
            installationDigest: journal.installationDigest,
            tombstoneDigest: journal.tombstoneDigest,
            updatedAt: journal.updatedAt
        )
        try StoreJSONCodec.write(tampered, to: store.paths.journalURL)

        XCTAssertEqual(try store.load(), .recoveryRequired(.integrityFailure))
    }

    func testMarkerAndTombstoneOperationsRemainDeferredUntilTheirFilesExist() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        let document = TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "safe")

        XCTAssertThrowsError(try store.commit(document, operation: .firstCompletedProfile)) { error in
            XCTAssertEqual(error as? PersistenceError, .unsupportedOperation)
        }
        XCTAssertThrowsError(try store.commit(document, operation: .profileDeletion)) { error in
            XCTAssertEqual(error as? PersistenceError, .unsupportedOperation)
        }
    }

    func testNonOwnerOnlyStateFileRequiresRecovery() throws {
        let directory = try temporaryDirectory()
        let store = try JournaledStateStore<TestDocument>(directory: directory)
        try store.commit(TestDocument(storeRevision: DecimalUInt64(rawValue: 1), value: "safe"), operation: .measurementSample)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: store.paths.canonicalURL.path
        )

        XCTAssertEqual(try store.load(), .recoveryRequired(.permissionModeFailure))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hbf-\(UUID().uuidString)", isDirectory: true)
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
