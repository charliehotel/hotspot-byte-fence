import Foundation

public extension JournaledStateStore where Document == StoreEnvelopeV1 {
    func commitEnvelope(_ document: StoreEnvelopeV1, operation: JournalOperation) throws {
        guard document.installationID == installationID else {
            throw PersistenceError.validationFailed
        }
        try document.validateSelfBinding()
        try commit(document, operation: operation)
    }

    func commitEnvelopeFirstCompletedProfile(
        _ document: StoreEnvelopeV1,
        marker: InstallationMarkerV1
    ) throws {
        guard document.installationID == installationID else {
            throw PersistenceError.validationFailed
        }
        try document.validateSelfBinding()
        try commitFirstCompletedProfile(document, marker: marker)
    }

    func commitEnvelopeProfileDeletion(
        _ document: StoreEnvelopeV1,
        tombstones: TombstoneSetV1
    ) throws {
        guard document.installationID == installationID else {
            throw PersistenceError.validationFailed
        }
        try document.validateSelfBinding()
        guard document.tombstoneDigest == (try tombstones.canonicalDigest()) else {
            throw PersistenceError.validationFailed
        }
        try commitProfileDeletion(document, tombstones: tombstones)
    }

    func loadEnvelope() throws -> StoreLoadResult<StoreEnvelopeV1> {
        let result = try load()
        if case let .loaded(envelope) = result {
            do {
                try envelope.validateSelfBinding()
            } catch {
                return .recoveryRequired(.integrityFailure)
            }
        }
        return result
    }
}
