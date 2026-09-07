import XCTest
@testable import HotspotByteFenceCore

final class AppUpdateTests: XCTestCase {
    func testInstallerSwapAndRollbackWithQuotedPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hbf-update-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let current = directory.appendingPathComponent("current ' $ app")
        let staged = directory.appendingPathComponent("staged app")
        let backup = directory.appendingPathComponent("backup app")
        try Data("old".utf8).write(to: current)
        try Data("new".utf8).write(to: staged)
        func install() throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", AppUpdatePolicy.installScript.replacingOccurrences(of: "/usr/bin/open", with: "/usr/bin/true"), "test", "2147483647", staged.path, current.path, backup.path]
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        XCTAssertEqual(try install(), 0)
        XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), "old")
        try FileManager.default.removeItem(at: backup)
        XCTAssertEqual(try install(), 1)
        XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
    }

    func testReleaseAndInstallationBoundaries() throws {
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("v0.10.0")), try XCTUnwrap(ReleaseVersion("0.9.9")))
        XCTAssertGreaterThan(try XCTUnwrap(ReleaseVersion("0.1.0")), try XCTUnwrap(ReleaseVersion("0.1.0-dev")))
        for invalid in ["", "v", "-", "+", "1..0", "-1.0.0", "latest", "1.2"] {
            XCTAssertNil(ReleaseVersion(invalid), invalid)
        }
        let digest = "sha256:" + String(repeating: "a", count: 64)
        func release(tag: String = "v0.2.0", prerelease: Bool = false, host: String = "github.com", hash: String = digest) throws -> AppRelease {
            let value: [String: Any] = [
                "tag_name": tag, "draft": false, "prerelease": prerelease,
                "assets": [["name": "HotspotByteFence-0.2.0-unsigned.zip", "browser_download_url": "https://\(host)/charliehotel/hotspot-byte-fence/releases/download/v0.2.0/app.zip", "digest": hash, "size": 100]]
            ]
            return try JSONDecoder().decode(AppRelease.self, from: JSONSerialization.data(withJSONObject: value))
        }
        XCTAssertTrue(try release().isNewer(than: "0.1.0"))
        XCTAssertFalse(try release().isNewer(than: "0.2.0"))
        XCTAssertFalse(try release(prerelease: true).isNewer(than: "0.1.0"))
        XCTAssertFalse(try release(tag: "v0.3.0-beta").isNewer(than: "0.1.0"))
        XCTAssertNotNil(try release().installAsset)
        XCTAssertNil(try release(host: "example.com").installAsset)
        XCTAssertNil(try release(hash: "sha256:bad").installAsset)
        XCTAssertTrue(AppUpdatePolicy.safeArchivePaths("HotspotByteFence.app/\nHotspotByteFence.app/Contents/Info.plist\n"))
        XCTAssertFalse(AppUpdatePolicy.safeArchivePaths("HotspotByteFence.app/../../outside"))
        XCTAssertFalse(AppUpdatePolicy.safeArchivePaths("/tmp/HotspotByteFence.app/file"))
        XCTAssertFalse(AppUpdatePolicy.safeArchivePaths(""))
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(AppUpdatePolicy.shouldCheck(now: now, lastAttempt: nil))
        XCTAssertFalse(AppUpdatePolicy.shouldCheck(now: now, lastAttempt: now.addingTimeInterval(-86_399)))
        XCTAssertTrue(AppUpdatePolicy.shouldCheck(now: now, lastAttempt: now.addingTimeInterval(-86_400)))
        XCTAssertTrue(AppUpdatePolicy.shouldCheck(now: now, lastAttempt: now.addingTimeInterval(1)))
    }
}
