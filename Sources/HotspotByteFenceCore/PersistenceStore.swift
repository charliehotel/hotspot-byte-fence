import Foundation

public final class JournaledStateStore<Document: VersionedDocument>: @unchecked Sendable {
    public let paths: StorePaths
    public let installationID: UUID

    public init(directory: URL, installationID: UUID? = nil) throws {
        self.paths = StorePaths(directory: directory)
        try Self.prepareDirectory(at: paths.directory)
        let existingID = Self.readExistingInstallationID(from: paths.journalURL)
            ?? Self.readExistingInstallationMarkerID(from: paths.installationURL)
        self.installationID = installationID ?? existingID ?? UUID()
    }

    public func decodeLKG() throws -> Document {
        try decodeFile(at: paths.lkgURL)
    }

    public func commit(_ document: Document, operation: JournalOperation) throws {
        guard operation.usesOnlyCanonicalAndLKG else {
            throw PersistenceError.unsupportedOperation
        }
        let canonicalData = try StoreJSONCodec.encode(document)
        let prepared = CommitJournalV1(
            installationID: installationID,
            operation: operation,
            targetStoreRevision: document.storeRevision,
            phase: .prepared,
            canonicalDigest: try digestIfPresent(at: paths.canonicalURL),
            lkgDigest: try digestIfPresent(at: paths.lkgURL),
            tombstoneDigest: operation == .recoveryFromLKG
                ? try digestIfPresent(at: paths.tombstonesURL)
                : nil
        )
        try writeJournal(prepared)

        try StoreJSONCodec.writeAtomicallyAndFlush(canonicalData, to: paths.canonicalURL, permissions: 0o600)
        try validateFile(at: paths.canonicalURL, equals: document)
        let canonicalDigest = try digest(at: paths.canonicalURL)
        let canonicalCommitted = try prepared.advancing(
            to: .canonicalCommitted,
            canonicalDigest: canonicalDigest
        )
        try writeJournal(canonicalCommitted)

        try StoreJSONCodec.writeAtomicallyAndFlush(canonicalData, to: paths.lkgURL, permissions: 0o600)
        try validateFile(at: paths.lkgURL, equals: document)
        let lkgCommitted = try canonicalCommitted.advancing(
            to: .lkgCommitted,
            lkgDigest: try digest(at: paths.lkgURL)
        )
        try writeJournal(lkgCommitted)
        try writeJournal(try lkgCommitted.advancing(to: .complete))
    }

    public func recoverFromLKG() throws -> Document {
        let document = try decodeLKG()
        try commit(document, operation: .recoveryFromLKG)
        return document
    }

    func readJournalIfPresent() throws -> CommitJournalV1? {
        guard FileManager.default.fileExists(atPath: paths.journalURL.path) else {
            return nil
        }
        return try StoreJSONCodec.decode(
            CommitJournalV1.self,
            from: Data(contentsOf: paths.journalURL)
        )
    }

    func writeJournal(_ journal: CommitJournalV1) throws {
        try StoreJSONCodec.write(journal, to: paths.journalURL)
    }

    func decodeFile(at url: URL) throws -> Document {
        try StoreJSONCodec.decode(Document.self, from: Data(contentsOf: url))
    }

    func validateFile(at url: URL, equals expected: Document) throws {
        let actual = try decodeFile(at: url)
        guard actual == expected, actual.storeRevision == expected.storeRevision else {
            throw PersistenceError.validationFailed
        }
    }

    func digest(at url: URL) throws -> String {
        StoreJSONCodec.sha256Hex(try Data(contentsOf: url))
    }

    func digestIfPresent(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try digest(at: url)
    }

    private static func prepareDirectory(at url: URL) throws {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw PersistenceError.directoryTypeMismatch
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: NSNumber(value: 0o700)]
                )
            } catch {
                throw PersistenceError.directoryCreationFailed
            }
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: url.path
        )
    }

    private static func readExistingInstallationID(from url: URL) -> UUID? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let journal = try? StoreJSONCodec.decode(CommitJournalV1.self, from: data) else {
            return nil
        }
        return journal.installationID
    }

    private static func readExistingInstallationMarkerID(from url: URL) -> UUID? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let marker = try? StoreJSONCodec.decode(InstallationMarkerV1.self, from: data) else {
            return nil
        }
        return marker.installationID
    }

    func hasPermissions(_ expected: UInt16, at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let value = attributes[.posixPermissions] else {
            return false
        }
        if let number = value as? NSNumber {
            return number.uint16Value == expected
        }
        if let permissions = value as? UInt16 {
            return permissions == expected
        }
        return false
    }
}
