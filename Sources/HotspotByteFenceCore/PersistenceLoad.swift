import Foundation

public extension JournaledStateStore {
    func load() throws -> StoreLoadResult<Document> {
        let journal: CommitJournalV1?
        do {
            journal = try readJournalIfPresent()
        } catch {
            return .recoveryRequired(.journalDecodeFailure)
        }
        if let journal, journal.phase != .complete {
            return .recoveryRequired(.incompleteJournal)
        }

        let fileManager = FileManager.default
        guard hasPermissions(0o700, at: paths.directory) else {
            return .recoveryRequired(.permissionModeFailure)
        }
        let canonicalExists = fileManager.fileExists(atPath: paths.canonicalURL.path)
        let lkgExists = fileManager.fileExists(atPath: paths.lkgURL.path)
        let markerExists = fileManager.fileExists(atPath: paths.installationURL.path)
        let tombstonesExist = fileManager.fileExists(atPath: paths.tombstonesURL.path)
        let existingFiles = [
            paths.canonicalURL,
            paths.lkgURL,
            paths.installationURL,
            paths.tombstonesURL,
            paths.journalURL
        ]
            .filter { fileManager.fileExists(atPath: $0.path) }
        guard existingFiles.allSatisfy({ hasPermissions(0o600, at: $0) }) else {
            return .recoveryRequired(.permissionModeFailure)
        }
        guard canonicalExists else {
            return lkgExists || journal != nil
                ? .recoveryRequired(.canonicalMissing)
                : .firstRun
        }
        guard lkgExists else {
            return .recoveryRequired(.lkgMissing)
        }

        let canonical: Document
        do {
            canonical = try decodeFile(at: paths.canonicalURL)
        } catch {
            return .recoveryRequired(.canonicalDecodeFailure)
        }

        let lkg: Document
        do {
            lkg = try decodeFile(at: paths.lkgURL)
        } catch {
            return .recoveryRequired(.lkgDecodeFailure)
        }
        guard canonical == lkg else {
            return .recoveryRequired(.integrityFailure)
        }

        let canonicalDigest: String
        do {
            canonicalDigest = try digest(at: paths.canonicalURL)
        } catch {
            return .recoveryRequired(.integrityFailure)
        }
        if markerExists {
            let marker: InstallationMarkerV1
            do {
                marker = try StoreJSONCodec.decode(
                    InstallationMarkerV1.self,
                    from: Data(contentsOf: paths.installationURL)
                )
            } catch {
                return .recoveryRequired(.installationDecodeFailure)
            }
            guard marker.matches(
                installationID: installationID,
                canonicalRevision: canonical.storeRevision,
                canonicalDigest: canonicalDigest
            ) else {
                return .recoveryRequired(.integrityFailure)
            }
        }

        let tombstones: TombstoneSetV1?
        if tombstonesExist {
            do {
                tombstones = try StoreJSONCodec.decode(
                    TombstoneSetV1.self,
                    from: Data(contentsOf: paths.tombstonesURL)
                )
            } catch {
                return .recoveryRequired(.tombstoneDecodeFailure)
            }
            if tombstones?.isPurgePending == true {
                return .recoveryRequired(.incompleteJournal)
            }
        } else {
            tombstones = nil
        }

        if let journal {
            guard journal.installationID == installationID,
                  journal.schemaVersion == 1,
                  journal.targetStoreRevision == canonical.storeRevision,
                  let journalCanonicalDigest = journal.canonicalDigest,
                  let journalLKGDigest = journal.lkgDigest else {
                return .recoveryRequired(.integrityFailure)
            }
            do {
                let actualCanonicalDigest = try digest(at: paths.canonicalURL)
                let actualLKGDigest = try digest(at: paths.lkgURL)
                guard journalCanonicalDigest == actualCanonicalDigest,
                      journalLKGDigest == actualLKGDigest else {
                    return .recoveryRequired(.integrityFailure)
                }
            } catch {
                return .recoveryRequired(.integrityFailure)
            }

            switch journal.operation {
            case .firstCompletedProfile:
                guard markerExists,
                      let markerDigest = journal.installationDigest,
                      markerDigest == (try? digest(at: paths.installationURL)) else {
                    return .recoveryRequired(.integrityFailure)
                }
            case .profileDeletion:
                guard let tombstones,
                      tombstones.isPurgeCompleted,
                      let tombstoneDigest = journal.tombstoneDigest,
                      tombstoneDigest == (try? digest(at: paths.tombstonesURL)) else {
                    return .recoveryRequired(.integrityFailure)
                }
            case .recoveryFromLKG:
                let actualTombstoneDigest: String?
                do {
                    actualTombstoneDigest = try digestIfPresent(at: paths.tombstonesURL)
                } catch {
                    return .recoveryRequired(.integrityFailure)
                }
                guard journal.tombstoneDigest == actualTombstoneDigest else {
                    return .recoveryRequired(.integrityFailure)
                }
            default:
                guard journal.operation.usesOnlyCanonicalAndLKG else {
                    return .recoveryRequired(.integrityFailure)
                }
            }
        }
        return .loaded(canonical)
    }
}
