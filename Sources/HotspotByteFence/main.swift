import Foundation
import HotspotByteFenceCore

@main
struct HotspotByteFence {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe-counter" {
#if canImport(Darwin)
            let counters = try DarwinInterfaceCounterSource().read(interfaceName: CommandLine.arguments[2])
            print("\(CommandLine.arguments[2]) rx=\(counters.rx) tx=\(counters.tx) total=\(counters.total)")
#else
            print("Counter probe is available only on Darwin")
#endif
            return
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--probe-identity" {
#if canImport(CoreWLAN)
            let observations = try CoreWLANIdentityAdapter().readAll()
            let associatedCount = observations.reduce(into: 0) { count, observation in
                if case .associated = observation {
                    count += 1
                }
            }
            let unavailableCount = observations.reduce(into: 0) { count, observation in
                if case .identityUnavailable = observation {
                    count += 1
                }
            }
            print("interfaces=\(observations.count) associated=\(associatedCount) identityUnavailable=\(unavailableCount)")
#else
            print("Identity probe is available only on CoreWLAN platforms")
#endif
            return
        }
        try BuildConfiguration.validate(BuildConfiguration.manifest)
        print("HotspotByteFence \(BuildConfiguration.manifest.applicationVersion) \(BuildConfiguration.manifest.compiledMode.rawValue)")
    }
}
