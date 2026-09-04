import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

public enum LoginItemStatus: String, Codable, Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unsupported
}

public protocol LoginItemControlling: Sendable {
    func status() -> LoginItemStatus
    func register() throws
    func unregister() throws
}

#if canImport(ServiceManagement)
public final class DarwinLoginItemController: LoginItemControlling {
    public init() {}

    public func status() -> LoginItemStatus {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .notRegistered: return .notRegistered
            case .requiresApproval: return .requiresApproval
            case .notFound: return .notFound
            @unknown default: return .unsupported
            }
        } else {
            return .unsupported
        }
    }

    public func register() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
        }
    }

    public func unregister() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
        }
    }
}
#endif

public final class MockLoginItemController: LoginItemControlling, @unchecked Sendable {
    public var currentStatus: LoginItemStatus
    public var registerCalled: Bool = false
    public var unregisterCalled: Bool = false

    public init(status: LoginItemStatus = .notRegistered) {
        self.currentStatus = status
    }

    public func status() -> LoginItemStatus {
        currentStatus
    }

    public func register() throws {
        registerCalled = true
        currentStatus = .enabled
    }

    public func unregister() throws {
        unregisterCalled = true
        currentStatus = .notRegistered
    }
}
