import Foundation

public extension JournaledStateStore where Document == StoreEnvelopeV1 {
    func commitEnvelope(_ document: StoreEnvelopeV1, operation: JournalOperation) throws {
        guard document.installationID == installationID else {
            throw PersistenceError.validationFailed
        }
        try commit(document, operation: operation)
    }
}
