#if canImport(CoreWLAN) && canImport(Darwin)
import CoreWLAN
import Darwin

public enum WiFiIdentityObservation: Equatable, Sendable {
    case associated(WiFiIdentitySnapshot)
    case notAssociated(interfaceName: String, interfaceIndex: UInt32)
    case identityUnavailable(interfaceName: String, interfaceIndex: UInt32)
}

public enum WiFiIdentityAdapterError: Error, Equatable, Sendable {
    case interfaceUnavailable
    case interfaceNameUnavailable
    case identityUnavailable
    case inconsistentReads
}

public final class CoreWLANIdentityAdapter: @unchecked Sendable, WiFiIdentitySource {
    private let client: CWWiFiClient

    public init(client: CWWiFiClient = CWWiFiClient.shared()) {
        self.client = client
    }

    public func read(interfaceName: String) throws -> WiFiIdentityObservation {
        guard let interface = client.interfaces()?.first(where: { $0.interfaceName == interfaceName }) else {
            throw WiFiIdentityAdapterError.interfaceUnavailable
        }
        let first = try readOnce(interface)
        let second = try readOnce(interface)
        switch (first, second) {
        case let (.associated(firstSnapshot), .associated(secondSnapshot)):
            do {
                return .associated(try StableIdentitySnapshot.requireEqual(firstSnapshot, secondSnapshot))
            } catch {
                throw WiFiIdentityAdapterError.inconsistentReads
            }
        case let (.notAssociated(firstName, firstIndex), .notAssociated(secondName, secondIndex)):
            guard firstName == secondName, firstIndex == secondIndex else {
                throw WiFiIdentityAdapterError.inconsistentReads
            }
            return .notAssociated(interfaceName: firstName, interfaceIndex: firstIndex)
        case let (.identityUnavailable(firstName, firstIndex), .identityUnavailable(secondName, secondIndex)):
            guard firstName == secondName, firstIndex == secondIndex else {
                throw WiFiIdentityAdapterError.inconsistentReads
            }
            return .identityUnavailable(interfaceName: firstName, interfaceIndex: firstIndex)
        default:
            throw WiFiIdentityAdapterError.inconsistentReads
        }
    }

    public func readAll() throws -> [WiFiIdentityObservation] {
        try (client.interfaces() ?? []).map { interface in
            guard let name = interface.interfaceName else {
                throw WiFiIdentityAdapterError.interfaceNameUnavailable
            }
            return try read(interfaceName: name)
        }
    }

    private func readOnce(_ interface: CWInterface) throws -> WiFiIdentityObservation {
        guard let name = interface.interfaceName, !name.isEmpty else {
            throw WiFiIdentityAdapterError.interfaceNameUnavailable
        }
        let index = name.withCString { if_nametoindex($0) }
        guard index != 0 else {
            throw WiFiIdentityAdapterError.interfaceUnavailable
        }
        guard interface.serviceActive() else {
            return .notAssociated(interfaceName: name, interfaceIndex: index)
        }
        guard let ssidData = interface.ssidData(),
              let bssidText = interface.bssid() else {
            return .identityUnavailable(interfaceName: name, interfaceIndex: index)
        }
        guard let ssid = try? SSID(bytes: Array(ssidData)),
              let bssid = try? BSSID(string: bssidText) else {
            throw WiFiIdentityAdapterError.identityUnavailable
        }
        return .associated(WiFiIdentitySnapshot(
            interfaceName: name,
            interfaceIndex: index,
            linkState: .associated,
            ssid: ssid,
            bssid: bssid
        ))
    }
}
#endif
