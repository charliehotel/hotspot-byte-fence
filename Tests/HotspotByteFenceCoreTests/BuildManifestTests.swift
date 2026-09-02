import XCTest
@testable import HotspotByteFenceCore

final class BuildManifestTests: XCTestCase {
    func testDevelopmentManifestDefaultsToMeasurementOnly() throws {
        XCTAssertEqual(BuildConfiguration.manifest.compiledMode, .measurementOnly)
        XCTAssertNoThrow(try BuildConfiguration.validate(BuildConfiguration.manifest))
    }

    func testManifestValidationRejectsCompileModeMismatch() {
        let manifest = BuildManifestV1(
            applicationVersion: "0.1.0-dev",
            sourceRevision: nil,
            compiledMode: .strongBlockingCapable
        )

        XCTAssertThrowsError(try BuildConfiguration.validate(manifest)) { error in
            XCTAssertEqual(error as? BuildManifestError, .compiledModeMismatch)
        }
    }

    func testCanonicalManifestJSONIsDeterministicAndSorted() throws {
        let first = try BuildConfiguration.canonicalJSON(BuildConfiguration.manifest)
        let second = try BuildConfiguration.canonicalJSON(BuildConfiguration.manifest)

        XCTAssertEqual(first, second)
        XCTAssertEqual(String(decoding: first, as: UTF8.self).first, "{")
    }
}
