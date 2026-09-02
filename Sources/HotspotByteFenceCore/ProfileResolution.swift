public enum ProfileResolution: Equatable, Sendable {
    case disconnected
    case connected(ProfileID)
    case unknownNetwork
    case needsBSSIDConfirmation([ProfileID])
    case ambiguous([ProfileID])
    case multipleProfilesConnected([ProfileID])
}

public enum ProfileResolver {
    public static func resolve(
        profiles: [ProfileDefinition],
        snapshots: [WiFiIdentitySnapshot]
    ) -> ProfileResolution {
        let associated = snapshots.filter { $0.linkState == .associated }
        guard !associated.isEmpty else {
            return .disconnected
        }

        var exactMatches: [ProfileID] = []
        var bssidCandidates: [ProfileID] = []
        for snapshot in associated {
            let exact = profiles.filter { $0.identity.matchesExact(snapshot) }
            if exact.count > 1 {
                return .ambiguous(exact.map(\.id))
            }
            if let match = exact.first {
                exactMatches.append(match.id)
                continue
            }
            bssidCandidates.append(contentsOf: profiles
                .filter { $0.identity.matchesInterfaceAndSSID(snapshot) }
                .map(\.id))
        }

        let uniqueExact = unique(exactMatches)
        if uniqueExact.count > 1 {
            return .multipleProfilesConnected(uniqueExact)
        }
        let candidates = unique(bssidCandidates)
        if !candidates.isEmpty {
            return .needsBSSIDConfirmation(candidates)
        }
        if let connected = uniqueExact.first {
            return .connected(connected)
        }
        return .unknownNetwork
    }

    private static func unique(_ ids: [ProfileID]) -> [ProfileID] {
        ids.reduce(into: []) { result, id in
            if !result.contains(id) {
                result.append(id)
            }
        }
    }
}
