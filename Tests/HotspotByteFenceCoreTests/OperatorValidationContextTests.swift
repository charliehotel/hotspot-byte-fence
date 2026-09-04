import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class OperatorValidationContextTests: XCTestCase {
    private let sampleSHA = String(repeating: "a", count: 64)
    private let otherSHA = String(repeating: "b", count: 64)

    private func makeDigests(sha: String? = nil) throws -> CandidateDigestSetV1 {
        let value = sha ?? sampleSHA
        return try CandidateDigestSetV1(
            unsignedAssetSHA256: value,
            appBundleSHA256: value,
            executableSHA256: value,
            embeddedManifestSHA256: value
        )
    }

    private func makeContext(
        gateID: String = "F-06",
        caseID: String = "case-001",
        operatorConfirmed: Bool = true,
        confirmedAt: Date = Date(),
        digests: CandidateDigestSetV1? = nil
    ) throws -> OperatorValidationContextV1 {
        let confirmation = try OperatorConfirmationRecordV1(
            confirmedAt: confirmedAt,
            operatorConfirmed: operatorConfirmed,
            targetInterfaceName: "en0",
            targetSSIDHex: "486f7473706f74",
            targetBSSID: "00:11:22:33:44:55",
            topologyRole: .t1
        )
        return try OperatorValidationContextV1(
            runID: UUID(),
            digests: digests ?? (try makeDigests()),
            gateID: gateID,
            caseID: caseID,
            operatorConfirmation: confirmation
        )
    }

    func testContextValidationSucceedsForFreshMatchingContext() throws {
        let now = Date()
        let digests = try makeDigests()
        let context = try makeContext(confirmedAt: now, digests: digests)

        let result = OperatorValidationContextValidator.validate(
            context: context,
            candidateDigests: digests,
            currentGateID: "F-06",
            currentCaseID: "case-001",
            now: now
        )
        XCTAssertEqual(result, .valid)
    }

    func testMissingContextYieldsMissingContext() throws {
        let digests = try makeDigests()
        let result = OperatorValidationContextValidator.validate(
            context: nil,
            candidateDigests: digests,
            currentGateID: "F-06",
            currentCaseID: "case-001"
        )
        XCTAssertEqual(result, .missingContext)
    }

    func testUnconfirmedYieldsUnconfirmed() throws {
        let now = Date()
        let digests = try makeDigests()
        let context = try makeContext(operatorConfirmed: false, confirmedAt: now, digests: digests)

        let result = OperatorValidationContextValidator.validate(
            context: context,
            candidateDigests: digests,
            currentGateID: "F-06",
            currentCaseID: "case-001",
            now: now
        )
        XCTAssertEqual(result, .unconfirmed)
    }

    func testDigestMismatchYieldsDigestMismatch() throws {
        let now = Date()
        let contextDigests = try makeDigests(sha: sampleSHA)
        let candidateDigests = try makeDigests(sha: otherSHA)
        let context = try makeContext(confirmedAt: now, digests: contextDigests)

        let result = OperatorValidationContextValidator.validate(
            context: context,
            candidateDigests: candidateDigests,
            currentGateID: "F-06",
            currentCaseID: "case-001",
            now: now
        )
        XCTAssertEqual(result, .digestMismatch)
    }

    func testGateOrCaseMismatchYieldsGateOrCaseMismatch() throws {
        let now = Date()
        let digests = try makeDigests()
        let context = try makeContext(gateID: "F-06", caseID: "case-001", confirmedAt: now, digests: digests)

        let wrongGate = OperatorValidationContextValidator.validate(
            context: context,
            candidateDigests: digests,
            currentGateID: "F-07",
            currentCaseID: "case-001",
            now: now
        )
        XCTAssertEqual(wrongGate, .gateOrCaseMismatch)

        let wrongCase = OperatorValidationContextValidator.validate(
            context: context,
            candidateDigests: digests,
            currentGateID: "F-06",
            currentCaseID: "case-002",
            now: now
        )
        XCTAssertEqual(wrongCase, .gateOrCaseMismatch)
    }

    func testStaleContextYieldsStaleContext() throws {
        let now = Date()
        let oldDate = now.addingTimeInterval(-301)
        let digests = try makeDigests()
        let context = try makeContext(confirmedAt: oldDate, digests: digests)

        let result = OperatorValidationContextValidator.validate(
            context: context,
            candidateDigests: digests,
            currentGateID: "F-06",
            currentCaseID: "case-001",
            now: now
        )
        XCTAssertEqual(result, .staleContext)
    }

   func testCandidateLifecycleSafetyGuaranteesBlockingNotGuaranteed() throws {
        let now = Date()
        let profile = try ProfileRecord(
            profileID: UUID(),
            aliasNFC: "Hotspot",
            ssidHex: "486f7473706f74",
            interfaceName: "en0",
            confirmedBSSIDs: [try BSSID(string: "00:11:22:33:44:55")],
            isComplete: true,
            sharesInterfaceSSID: false,
            limitBytes: ByteCount(100_000_000),
            resetDay: 1,
            cycle: try CycleRecord(
                cycleID: CycleID(effectiveDate: "2026-09-01", timeZoneID: "Asia/Seoul"),
                wallClock: now
            ),
            measurement: try MeasurementRecord.initial(),
            protection: try ProtectionRecord(
                limitReached: false,
                pauseBlocking: false,
                blockingCapability: .strongReady,
                lastAuthorizationOutcome: .granted,
                retry: try RetryRecord(
                    state: .none,
                    attemptIndex: 0,
                    nextEligibleAt: nil,
                    lastAttemptAt: nil
                ),
                lastSuppressionObservation: nil,
                lastFailureReason: nil,
                ownedTransactionID: nil
            ),
            createdAt: now,
            updatedAt: now
        )

        let normalState: ProtectionState = RuntimeSnapshotV1.evaluateProtectionState(
            globalSafety: .normal,
            profile: profile,
            hasRestorationConflict: false,
            candidateLifecycle: .production
        )
        XCTAssertEqual(normalState, ProtectionState.strongBlockingReady)

        let candidateState: ProtectionState = RuntimeSnapshotV1.evaluateProtectionState(
            globalSafety: .normal,
            profile: profile,
            hasRestorationConflict: false,
            candidateLifecycle: .operatorValidation
        )
        XCTAssertEqual(candidateState, ProtectionState.blockingNotGuaranteed)
    }
}
