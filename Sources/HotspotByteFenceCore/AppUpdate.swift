import Foundation

public struct ReleaseVersion: Comparable, Sendable {
    public let numbers: [Int]
    public let isPrerelease: Bool

    public init?(_ text: String) {
        let text = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let core = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              numbers.compactMap({ Int($0) }).count == 3 else { return nil }
        self.numbers = numbers.compactMap { Int($0) }
        isPrerelease = parts.count > 1
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        return lhs.isPrerelease && !rhs.isPrerelease
    }
}

public struct AppRelease: Codable, Sendable {
    public struct Asset: Codable, Sendable {
        public let name: String
        public let browser_download_url: URL
        public let digest: String?
        public let size: Int
    }
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    public func isNewer(than current: String) -> Bool {
        guard !draft, !prerelease,
              let latest = ReleaseVersion(tag_name), !latest.isPrerelease,
              let installed = ReleaseVersion(current) else { return false }
        return latest > installed
    }

    public var installAsset: Asset? {
        assets.first {
            $0.name == "HotspotByteFence-\(tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name)-unsigned.zip"
                && $0.browser_download_url.scheme == "https"
                && $0.browser_download_url.host == "github.com"
                && $0.browser_download_url.path.hasPrefix("/charliehotel/hotspot-byte-fence/releases/download/")
                && $0.size > 0 && $0.size < 200_000_000
                && Self.validDigest($0.digest)
        }
    }

    public static func validDigest(_ digest: String?) -> Bool {
        guard let digest, digest.hasPrefix("sha256:") else { return false }
        let hex = digest.dropFirst(7)
        return hex.count == 64 && hex.allSatisfy { $0.isHexDigit && $0.isASCII }
    }
}

public enum AppUpdatePolicy {
    public static let installScript = """
    count=0
    while /bin/kill -0 "$1" 2>/dev/null; do
        count=$((count + 1))
        if [ "$count" -ge 60 ]; then /usr/bin/open -R "$2"; exit 1; fi
        /bin/sleep 1
    done
    if ! /bin/mv "$3" "$4"; then /usr/bin/open -R "$2"; exit 1; fi
    if ! /bin/mv "$2" "$3"; then
        /bin/mv "$4" "$3"
        /usr/bin/open "$3"
        exit 1
    fi
    if ! /usr/bin/open "$3"; then /usr/bin/open -R "$4"; exit 1; fi
    """

    public static let interval: TimeInterval = 24 * 60 * 60
    public static func shouldCheck(now: Date, lastAttempt: Date?) -> Bool {
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        return elapsed < 0 || elapsed >= interval
    }

    public static func safeArchivePaths(_ paths: String) -> Bool {
        let entries = paths.split(separator: "\n")
        return !entries.isEmpty && entries.allSatisfy { path in
            path.hasPrefix("HotspotByteFence.app/")
                && !path.split(separator: "/").contains("..")
                && !path.contains("\\")
        }
    }
}
