import XCTest
@testable import HotspotByteFenceCore

final class SafetyTests: XCTestCase {
    func testMeasurementOnlyBuildNeverBecomesStrongBlockingReady() {
        let decision = ProtectionEligibilityEvaluator.evaluate(
            ProtectionEligibilityInput(
                globalSafety: .normal,
                compiledMode: .measurementOnly,
                identityCapability: .passed,
                counterCapability: .passed,
                sharedInterfaceSSID: false,
                authorizationAvailable: true,
                exactTargetResolved: true,
                pauseBlocking: false
            )
        )

        XCTAssertEqual(decision, .blockingNotGuaranteed(.measurementOnlyBuild))
    }

    func testCounterCapabilityFailureHasRecoveryPrecedence() {
        let decision = ProtectionEligibilityEvaluator.evaluate(
            ProtectionEligibilityInput(
                globalSafety: .normal,
                compiledMode: .measurementOnly,
                identityCapability: .passed,
                counterCapability: .deterministicFailure,
                sharedInterfaceSSID: false,
                authorizationAvailable: true,
                exactTargetResolved: true,
                pauseBlocking: false
            )
        )

        XCTAssertEqual(decision, .recoveryRequired(.counterCapabilityFailure))
    }

    func testSharedScopeAndMissingAuthorizationRemainBlockingNotGuaranteed() {
        let shared = ProtectionEligibilityEvaluator.evaluate(
            ProtectionEligibilityInput(
                globalSafety: .normal,
                compiledMode: .strongBlockingCapable,
                identityCapability: .passed,
                counterCapability: .passed,
                sharedInterfaceSSID: true,
                authorizationAvailable: true,
                exactTargetResolved: true,
                pauseBlocking: false
            )
        )
        let unauthorized = ProtectionEligibilityEvaluator.evaluate(
            ProtectionEligibilityInput(
                globalSafety: .normal,
                compiledMode: .strongBlockingCapable,
                identityCapability: .passed,
                counterCapability: .passed,
                sharedInterfaceSSID: false,
                authorizationAvailable: false,
                exactTargetResolved: true,
                pauseBlocking: false
            )
        )

        XCTAssertEqual(shared, .blockingNotGuaranteed(.sharedInterfaceSSID))
        XCTAssertEqual(unauthorized, .blockingNotGuaranteed(.authorizationUnavailable))
    }

    func testAllStrongBlockingInputsCanProduceTheReadyDomainDecision() {
        let decision = ProtectionEligibilityEvaluator.evaluate(
            ProtectionEligibilityInput(
                globalSafety: .normal,
                compiledMode: .strongBlockingCapable,
                identityCapability: .passed,
                counterCapability: .passed,
                sharedInterfaceSSID: false,
                authorizationAvailable: true,
                exactTargetResolved: true,
                pauseBlocking: false
            )
        )

        XCTAssertEqual(decision, .strongBlockingReady)
    }
}
