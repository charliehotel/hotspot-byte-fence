public enum GlobalSafetyState: String, Codable, Equatable, Sendable {
    case normal
    case recoveryRequired
    case timeAdjustmentRequired
    case multipleProfilesConnected
}

public enum IdentityCapabilityStatus: String, Codable, Equatable, Sendable {
    case pending
    case passed
    case failed
}

public enum CounterCapabilityStatus: String, Codable, Equatable, Sendable {
    case pending
    case passed
    case deterministicFailure
}

public enum ProtectionNotReadyReason: String, Codable, Equatable, Sendable {
    case globalSafetyStop
    case identityCapabilityPending
    case identityCapabilityFailed
    case counterCapabilityPending
    case measurementOnlyBuild
    case sharedInterfaceSSID
    case authorizationUnavailable
    case targetNotResolved
    case paused
}

public enum ProtectionRecoveryReason: String, Codable, Equatable, Sendable {
    case counterCapabilityFailure
}

public struct ProtectionEligibilityInput: Equatable, Sendable {
    public let globalSafety: GlobalSafetyState
    public let compiledMode: CompiledMode
    public let identityCapability: IdentityCapabilityStatus
    public let counterCapability: CounterCapabilityStatus
    public let sharedInterfaceSSID: Bool
    public let authorizationAvailable: Bool
    public let exactTargetResolved: Bool
    public let pauseBlocking: Bool

    public init(
        globalSafety: GlobalSafetyState,
        compiledMode: CompiledMode,
        identityCapability: IdentityCapabilityStatus,
        counterCapability: CounterCapabilityStatus,
        sharedInterfaceSSID: Bool,
        authorizationAvailable: Bool,
        exactTargetResolved: Bool,
        pauseBlocking: Bool
    ) {
        self.globalSafety = globalSafety
        self.compiledMode = compiledMode
        self.identityCapability = identityCapability
        self.counterCapability = counterCapability
        self.sharedInterfaceSSID = sharedInterfaceSSID
        self.authorizationAvailable = authorizationAvailable
        self.exactTargetResolved = exactTargetResolved
        self.pauseBlocking = pauseBlocking
    }
}

public enum ProtectionEligibility: Equatable, Sendable {
    case strongBlockingReady
    case blockingNotGuaranteed(ProtectionNotReadyReason)
    case recoveryRequired(ProtectionRecoveryReason)
}

public enum ProtectionEligibilityEvaluator {
    public static func evaluate(_ input: ProtectionEligibilityInput) -> ProtectionEligibility {
        if input.counterCapability == .deterministicFailure {
            return .recoveryRequired(.counterCapabilityFailure)
        }
        guard input.globalSafety == .normal else {
            return .blockingNotGuaranteed(.globalSafetyStop)
        }
        switch input.identityCapability {
        case .pending:
            return .blockingNotGuaranteed(.identityCapabilityPending)
        case .failed:
            return .blockingNotGuaranteed(.identityCapabilityFailed)
        case .passed:
            break
        }
        guard input.counterCapability == .passed else {
            return .blockingNotGuaranteed(.counterCapabilityPending)
        }
        guard input.compiledMode == .strongBlockingCapable else {
            return .blockingNotGuaranteed(.measurementOnlyBuild)
        }
        guard !input.sharedInterfaceSSID else {
            return .blockingNotGuaranteed(.sharedInterfaceSSID)
        }
        guard input.authorizationAvailable else {
            return .blockingNotGuaranteed(.authorizationUnavailable)
        }
        guard input.exactTargetResolved else {
            return .blockingNotGuaranteed(.targetNotResolved)
        }
        guard !input.pauseBlocking else {
            return .blockingNotGuaranteed(.paused)
        }
        return .strongBlockingReady
    }
}
