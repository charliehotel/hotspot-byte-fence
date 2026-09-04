import Foundation

#if canImport(CoreWLAN) && canImport(Darwin)
import CoreWLAN
import Darwin

#if canImport(Security)
import Security
#endif

public final class CoreWLANPreferenceAdapter: @unchecked Sendable, WiFiPreferenceAdapterProtocol {
    private let client: CWWiFiClient
    private let identityAdapter: CoreWLANIdentityAdapter

    public init(client: CWWiFiClient = CWWiFiClient.shared()) {
        self.client = client
        self.identityAdapter = CoreWLANIdentityAdapter(client: client)
    }

    public func readConfiguration(interfaceName: String) throws -> CWConfigurationArchiveV1 {
        guard let interface = client.interfaces()?.first(where: { $0.interfaceName == interfaceName }) else {
            throw PreferenceTransactionExecutionError.configurationReadFailed
        }
        guard let config = interface.configuration() else {
            throw PreferenceTransactionExecutionError.configurationReadFailed
        }

        var networkProfiles: [CWNetworkProfileArchiveV1] = []
        for case let profile as CWNetworkProfile in config.networkProfiles {
            guard let ssidData = profile.ssidData,
                  let ssid = try? SSID(bytes: Array(ssidData)) else {
                continue
            }
            let secVal = UInt64(profile.security.rawValue)
            if let pArchive = try? CWNetworkProfileArchiveV1(ssid: ssid, securityRawValue: secVal) {
                networkProfiles.append(pArchive)
            }
        }
        networkProfiles.sort { $0.ssidHex < $1.ssidHex }

        let flags = CWConfigurationArchiveFlagsV1(
            requireAdministratorForAssociation: config.requireAdministratorForAssociation,
            requireAdministratorForIBSSMode: false,
            requireAdministratorForPower: config.requireAdministratorForPower,
            rememberJoinedNetworks: config.rememberJoinedNetworks
        )
        return CWConfigurationArchiveV1(networkProfiles: networkProfiles, flags: flags)
    }

    public func commitConfiguration(interfaceName: String, archive: CWConfigurationArchiveV1) throws {
        guard let interface = client.interfaces()?.first(where: { $0.interfaceName == interfaceName }) else {
            throw PreferenceTransactionExecutionError.commitFailed
        }
        guard let currentConfig = interface.configuration() else {
            throw PreferenceTransactionExecutionError.commitFailed
        }

        let mutableConfig = CWMutableConfiguration(configuration: currentConfig)
        var newProfiles: [CWNetworkProfile] = []
        for case let profile as CWNetworkProfile in currentConfig.networkProfiles {
            guard let ssidData = profile.ssidData,
                  let ssid = try? SSID(bytes: Array(ssidData)) else {
                continue
            }
            if archive.networkProfiles.contains(where: { $0.ssidHex == ssid.hex }) {
                newProfiles.append(profile)
            }
        }

        mutableConfig.networkProfiles = NSOrderedSet(array: newProfiles)
        mutableConfig.rememberJoinedNetworks = archive.rememberJoinedNetworks
        mutableConfig.requireAdministratorForAssociation = archive.requireAdministratorForAssociation
        mutableConfig.requireAdministratorForPower = archive.requireAdministratorForPower

        do {
            try interface.commitConfiguration(mutableConfig, authorization: nil)
        } catch {
            throw PreferenceTransactionExecutionError.commitFailed
        }
    }

    public func disassociate(interfaceName: String) throws {
        guard let interface = client.interfaces()?.first(where: { $0.interfaceName == interfaceName }) else {
            throw PreferenceTransactionExecutionError.commitFailed
        }
        interface.disassociate()
    }

    public func readCurrentIdentity(interfaceName: String) throws -> WiFiIdentityObservation {
        try identityAdapter.read(interfaceName: interfaceName)
    }
}
#endif
