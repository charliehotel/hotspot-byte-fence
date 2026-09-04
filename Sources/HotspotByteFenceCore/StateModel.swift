import Foundation

public enum ConnectionState: String, Codable, Equatable, Sendable {
    case monitoring
    case disconnected
    case unknownNetwork
    case needsBSSIDConfirmation
    case locationPermissionRequired
    case measurementUnavailable

    public var userFacingLabelKey: String {
        "state.connection.\(rawValue)"
    }
}

public enum SelectionState: String, Codable, Equatable, Sendable {
    case none
    case selectedDisconnected
    case selectedConnected

    public var userFacingLabelKey: String {
        "state.selection.\(rawValue)"
    }
}

public enum ProtectionState: String, Codable, Equatable, Sendable {
    case strongBlockingReady
    case limitReached
    case blockingFailed
    case blockingPaused
    case blockingNotGuaranteed
    case restorationConflict

    public var userFacingLabelKey: String {
        "state.protection.\(rawValue)"
    }
}

public enum CandidateLifecycle: String, Equatable, Sendable {
    case production
    case operatorValidation
}

public struct RuntimeSnapshotV1: Equatable, Sendable {
    public let globalSafety: GlobalSafetyState
    public let connectionState: ConnectionState
    public let selectionState: SelectionState
    public let protectionState: ProtectionState
    public let candidateLifecycle: CandidateLifecycle
    public let connectedProfileID: UUID?
    public let selectedProfileID: UUID?
    public let selectedProfileAlias: String?
    public let isPauseBlockingActive: Bool
    public let currentUsageBytes: ByteCount?
    public let currentLimitBytes: ByteCount?
    public let cycleID: CycleID?
    public let authorizationAvailable: Bool
    public let storeRevision: DecimalUInt64
    public let languageOverride: StoreLanguageOverrideV1
    public let activeTransactionPhase: PreferenceTransactionPhaseV1?
    public let recoveryReason: GlobalRecoveryReasonV1?
    public let timeAdjustmentReason: TimeAdjustmentReasonV1?

    public init(
        globalSafety: GlobalSafetyState,
        connectionState: ConnectionState,
        selectionState: SelectionState,
        protectionState: ProtectionState,
        candidateLifecycle: CandidateLifecycle,
        connectedProfileID: UUID? = nil,
        selectedProfileID: UUID? = nil,
        selectedProfileAlias: String? = nil,
        isPauseBlockingActive: Bool = false,
        currentUsageBytes: ByteCount? = nil,
        currentLimitBytes: ByteCount? = nil,
        cycleID: CycleID? = nil,
        authorizationAvailable: Bool = false,
        storeRevision: DecimalUInt64,
        languageOverride: StoreLanguageOverrideV1 = .system,
        activeTransactionPhase: PreferenceTransactionPhaseV1? = nil,
        recoveryReason: GlobalRecoveryReasonV1? = nil,
        timeAdjustmentReason: TimeAdjustmentReasonV1? = nil
    ) {
        self.globalSafety = globalSafety
        self.connectionState = connectionState
        self.selectionState = selectionState
        self.protectionState = protectionState
        self.candidateLifecycle = candidateLifecycle
        self.connectedProfileID = connectedProfileID
        self.selectedProfileID = selectedProfileID
        self.selectedProfileAlias = selectedProfileAlias
        self.isPauseBlockingActive = isPauseBlockingActive
        self.currentUsageBytes = currentUsageBytes
        self.currentLimitBytes = currentLimitBytes
        self.cycleID = cycleID
        self.authorizationAvailable = authorizationAvailable
        self.storeRevision = storeRevision
        self.languageOverride = languageOverride
        self.activeTransactionPhase = activeTransactionPhase
        self.recoveryReason = recoveryReason
        self.timeAdjustmentReason = timeAdjustmentReason
    }

    public static func evaluateSelectionState(
        selectedID: UUID?,
        connectedID: UUID?
    ) -> SelectionState {
        guard let selectedID else {
            return .none
        }
        if let connectedID, selectedID == connectedID {
            return .selectedConnected
        }
        return .selectedDisconnected
    }

    public static func evaluateProtectionState(
        globalSafety: GlobalSafetyState,
        profile: ProfileRecord?,
        hasRestorationConflict: Bool,
        candidateLifecycle: CandidateLifecycle
    ) -> ProtectionState {
        if hasRestorationConflict {
            return .restorationConflict
        }
        guard let profile else {
            return .blockingNotGuaranteed
        }
        if profile.protection.pauseBlocking {
            return .blockingPaused
        }
        if profile.protection.retry.state == .scheduled || profile.protection.retry.state == .running {
            return .blockingFailed
        }
        if profile.protection.limitReached {
            return .limitReached
        }
        if candidateLifecycle == .operatorValidation {
            return .blockingNotGuaranteed
        }
        if globalSafety == .normal,
           profile.protection.blockingCapability == .strongReady {
            return .strongBlockingReady
        }
        return .blockingNotGuaranteed
    }
}
