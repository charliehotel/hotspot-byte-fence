import Foundation

public enum DisassociateOutcome: Equatable, Sendable {
    case targetAbsent
    case targetStillPresent
    case unrelatedNetworkConnected
    case identityUnavailable
}

public enum PreferenceTransactionExecutionError: Error, Equatable, Sendable {
    case operatorValidationFailed(OperatorValidationResultV1)
    case identityMismatch
    case identityUnavailable
    case configurationReadFailed
    case commitFailed
    case readBackMismatch
    case disassociateVerificationFailed(DisassociateOutcome)
    case restorationOwnershipConflict
    case invalidTransactionState
}

public protocol WiFiPreferenceAdapterProtocol: Sendable {
    func readConfiguration(interfaceName: String) throws -> CWConfigurationArchiveV1
    func commitConfiguration(interfaceName: String, archive: CWConfigurationArchiveV1) throws
    func disassociate(interfaceName: String) throws
    func readCurrentIdentity(interfaceName: String) throws -> WiFiIdentityObservation
}

public protocol AuthorizationProviderProtocol: Sendable {
    var hasUsableAuthorization: Bool { get }
    func requestAuthorization() throws
    func invalidate()
}

public final class MockAuthorizationProvider: @unchecked Sendable, AuthorizationProviderProtocol {
    public var hasUsableAuthorization: Bool
    public var requestCallCount: Int = 0
    public var shouldThrowOnRequest: Bool = false

    public init(hasUsableAuthorization: Bool = true) {
        self.hasUsableAuthorization = hasUsableAuthorization
    }

    public func requestAuthorization() throws {
        requestCallCount += 1
        if shouldThrowOnRequest {
            throw PreferenceTransactionExecutionError.commitFailed
        }
        hasUsableAuthorization = true
    }

    public func invalidate() {
        hasUsableAuthorization = false
    }
}
