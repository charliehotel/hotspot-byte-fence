import Foundation

public final class MockWiFiPreferenceAdapter: @unchecked Sendable, WiFiPreferenceAdapterProtocol {
    public var currentArchive: CWConfigurationArchiveV1
    public var currentObservation: WiFiIdentityObservation
    public var observationSequence: [WiFiIdentityObservation] = []
    public var disassociateCallCount: Int = 0
    public var commitCallCount: Int = 0
    public var lastCommittedArchive: CWConfigurationArchiveV1?
    public var shouldThrowOnRead: Bool = false
    public var shouldThrowOnCommit: Bool = false
    public var shouldThrowOnDisassociate: Bool = false

    public init(
        currentArchive: CWConfigurationArchiveV1,
        currentObservation: WiFiIdentityObservation
    ) {
        self.currentArchive = currentArchive
        self.currentObservation = currentObservation
    }

    public func readConfiguration(interfaceName: String) throws -> CWConfigurationArchiveV1 {
        if shouldThrowOnRead {
            throw PreferenceTransactionExecutionError.configurationReadFailed
        }
        return currentArchive
    }

    public func commitConfiguration(interfaceName: String, archive: CWConfigurationArchiveV1) throws {
        if shouldThrowOnCommit {
            throw PreferenceTransactionExecutionError.commitFailed
        }
        commitCallCount += 1
        lastCommittedArchive = archive
        currentArchive = archive
    }

    public func disassociate(interfaceName: String) throws {
        if shouldThrowOnDisassociate {
            throw PreferenceTransactionExecutionError.commitFailed
        }
        disassociateCallCount += 1
        if observationSequence.isEmpty {
            currentObservation = .notAssociated(interfaceName: interfaceName, interfaceIndex: 1)
        }
    }

    public func readCurrentIdentity(interfaceName: String) throws -> WiFiIdentityObservation {
        if !observationSequence.isEmpty {
            return observationSequence.removeFirst()
        }
        return currentObservation
    }
}
