import Foundation

public struct RuntimeEngineState: Sendable {
    public var store: StoreEnvelopeV1
    public var candidateLifecycle: CandidateLifecycle
    public var processLifecycleID: UUID
    public var authorizationAvailable: Bool
    public var resolvedIdentity: WiFiIdentitySnapshot?
    public var connectionState: ConnectionState
    public var resolvedProfileID: UUID?
    public var measurementStates: [UUID: MeasurementState]
    public var activeObservationTracker: WiFiObservationWindowTracker?
    public var manualReconnectTokenExpiresAt: Date?
    public var lastAwakeTimestampNanoseconds: UInt64?

    public init(
        store: StoreEnvelopeV1,
        candidateLifecycle: CandidateLifecycle = .production,
        processLifecycleID: UUID = UUID(),
        authorizationAvailable: Bool = false,
        resolvedIdentity: WiFiIdentitySnapshot? = nil,
        connectionState: ConnectionState = .disconnected,
        resolvedProfileID: UUID? = nil,
        measurementStates: [UUID: MeasurementState] = [:],
        activeObservationTracker: WiFiObservationWindowTracker? = nil,
        manualReconnectTokenExpiresAt: Date? = nil,
        lastAwakeTimestampNanoseconds: UInt64? = nil
    ) {
        self.store = store
        self.candidateLifecycle = candidateLifecycle
        self.processLifecycleID = processLifecycleID
        self.authorizationAvailable = authorizationAvailable
        self.resolvedIdentity = resolvedIdentity
        self.connectionState = connectionState
        self.resolvedProfileID = resolvedProfileID
        self.measurementStates = measurementStates
        self.activeObservationTracker = activeObservationTracker
        self.manualReconnectTokenExpiresAt = manualReconnectTokenExpiresAt
        self.lastAwakeTimestampNanoseconds = lastAwakeTimestampNanoseconds
    }
}

public enum RuntimeEvent: Sendable {
    case storeFailure(GlobalRecoveryReasonV1)
    case arithmeticOverflow
    case counterDeterministicFailure
    case sleepOccurred
    case wakeOccurred(monotonicNanoseconds: UInt64)
    case voluntaryQuitRequested
    case backwardWallClockDetected(trustedCycleDate: String, observedCycleDate: String, timeZoneID: String)
    case divergenceDetected(trustedCycleDate: String, observedCycleDate: String, timeZoneID: String)
    case acknowledgeTimeAdjustment
    case forwardCycleTransition(profileID: UUID, newCycleID: CycleID)
    case changeResetDay(profileID: UUID, newResetDay: UInt)
    case locationPermissionChanged(isAvailable: Bool)
    case networkResolutionChanged(identity: WiFiIdentitySnapshot?)
    case confirmBSSID(profileID: UUID, bssid: BSSID)
    case authorizationChanged(isAvailable: Bool)
    case limitReached(profileID: UUID)
    case pauseBlockingToggled(profileID: UUID, isPaused: Bool)
    case manualResetUsage(profileID: UUID)
    case changeLimit(profileID: UUID, newLimitBytes: ByteCount)
    case createOrUpdateProfile(alias: String, limitBytes: ByteCount, resetDay: UInt, interfaceName: String, ssidHex: String, bssid: BSSID)
    case counterSampleIngested(sample: MeasurementSample)
    case selectProfile(profileID: UUID?)
    case setLanguageOverride(StoreLanguageOverrideV1)
    case muteFailureNotification(profileID: UUID, mute: ProfileFailureMuteV1, expiresAt: Date?, cycleDate: String?)
}

public enum RuntimeSideEffect: Equatable, Sendable {
    case persistStore(StoreEnvelopeV1)
    case emitSnapshot(RuntimeSnapshotV1)
    case disassociate(interfaceName: String)
    case requestAuthorization(profileID: UUID)
    case scheduleEnforcementRetry(profileID: UUID, delaySeconds: UInt)
}

public enum StateReducer {
    public static func reduce(
        state: RuntimeEngineState,
        event: RuntimeEvent
    ) -> (newState: RuntimeEngineState, effects: [RuntimeSideEffect]) {
        var newState = state
        var effects: [RuntimeSideEffect] = []

        switch event {
        case let .storeFailure(reason):
            if let updatedStore = try? updateGlobalSafety(
                store: newState.store,
                safety: .recoveryRequired,
                recoveryReason: reason,
                timeAdjustment: nil
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case .arithmeticOverflow:
            if let updatedStore = try? updateGlobalSafety(
                store: newState.store,
                safety: .recoveryRequired,
                recoveryReason: .arithmeticOverflow,
                timeAdjustment: nil
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case .counterDeterministicFailure:
            if let updatedStore = try? updateGlobalSafety(
                store: newState.store,
                safety: .recoveryRequired,
                recoveryReason: .counterCapabilityFailure,
                timeAdjustment: nil
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case .sleepOccurred:
            newState.connectionState = .disconnected
            newState.activeObservationTracker?.interrupt()
            for id in newState.measurementStates.keys {
                newState.measurementStates[id]?.baseline = nil
            }

        case let .wakeOccurred(monotonicNanoseconds):
            newState.lastAwakeTimestampNanoseconds = monotonicNanoseconds
            for id in newState.measurementStates.keys {
                newState.measurementStates[id]?.baseline = nil
            }

        case .voluntaryQuitRequested:
            newState.activeObservationTracker?.interrupt()

        case let .backwardWallClockDetected(trusted, observed, tz):
            if let adjustment = try? TimeAdjustmentRecord(
                reason: .backwardWallClock,
                trustedCycleDate: trusted,
                observedCycleDate: observed,
                timeZoneID: tz,
                observedAt: Date(),
                acknowledgementRequired: true
            ), let updatedStore = try? updateGlobalSafety(
                store: newState.store,
                safety: .timeAdjustmentRequired,
                recoveryReason: nil,
                timeAdjustment: adjustment
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case let .divergenceDetected(trusted, observed, tz):
            if let adjustment = try? TimeAdjustmentRecord(
                reason: .wallMonotonicDivergence,
                trustedCycleDate: trusted,
                observedCycleDate: observed,
                timeZoneID: tz,
                observedAt: Date(),
                acknowledgementRequired: true
            ), let updatedStore = try? updateGlobalSafety(
                store: newState.store,
                safety: .timeAdjustmentRequired,
                recoveryReason: nil,
                timeAdjustment: adjustment
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case .acknowledgeTimeAdjustment:
            if let updatedStore = try? updateGlobalSafety(
                store: newState.store,
                safety: .normal,
                recoveryReason: nil,
                timeAdjustment: nil
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case let .forwardCycleTransition(profileID, newCycleID):
            if let updatedStore = try? transitionProfileCycle(
                store: newState.store,
                profileID: profileID,
                newCycleID: newCycleID
            ) {
                newState.store = updatedStore
                newState.measurementStates[profileID]?.cycleID = newCycleID
                newState.measurementStates[profileID]?.usageBytes = ByteCount(0)
                newState.measurementStates[profileID]?.baseline = nil
                effects.append(.persistStore(updatedStore))
            }

        case let .changeResetDay(profileID, newDay):
            if let updatedStore = try? updateProfileResetDay(
                store: newState.store,
                profileID: profileID,
                newResetDay: newDay
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case let .locationPermissionChanged(isAvailable):
            if !isAvailable {
                newState.connectionState = .locationPermissionRequired
                newState.resolvedIdentity = nil
                newState.resolvedProfileID = nil
            }

        case let .networkResolutionChanged(identity):
            guard let identity else {
                newState.resolvedIdentity = nil
                newState.resolvedProfileID = nil
                newState.connectionState = .disconnected
                break
            }
            newState.resolvedIdentity = identity
            let matching = newState.store.profiles.filter { profile in
                profile.isComplete &&
                profile.interfaceName == identity.interfaceName &&
                profile.ssidHex == identity.ssid.hex
            }
            if matching.isEmpty {
                newState.resolvedProfileID = nil
                newState.connectionState = .unknownNetwork
            } else {
                let bssidMatch = matching.first { profile in
                    profile.confirmedBSSIDs.contains(identity.bssid)
                }
                if let bssidMatch {
                    newState.resolvedProfileID = bssidMatch.profileID
                    newState.connectionState = .monitoring
                } else {
                    newState.resolvedProfileID = nil
                    newState.connectionState = .needsBSSIDConfirmation
                }
            }

        case let .confirmBSSID(profileID, bssid):
            if let updatedStore = try? appendProfileBSSID(
                store: newState.store,
                profileID: profileID,
                bssid: bssid
            ) {
                newState.store = updatedStore
                if let resolved = newState.resolvedIdentity, resolved.bssid == bssid {
                    newState.resolvedProfileID = profileID
                    newState.connectionState = .monitoring
                }
                effects.append(.persistStore(updatedStore))
            }

        case let .authorizationChanged(isAvailable):
            newState.authorizationAvailable = isAvailable

        case let .limitReached(profileID):
            if let updatedStore = try? updateProfileLimitReached(
                store: newState.store,
                profileID: profileID,
                reached: true
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
                if let profile = updatedStore.profiles.first(where: { $0.profileID == profileID }),
                   let interfaceName = profile.interfaceName,
                   !profile.protection.pauseBlocking {
                    effects.append(.disassociate(interfaceName: interfaceName))
                }
            }

        case let .pauseBlockingToggled(profileID, isPaused):
            if let updatedStore = try? updateProfilePauseBlocking(
                store: newState.store,
                profileID: profileID,
                isPaused: isPaused
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case let .manualResetUsage(profileID):
            if let updatedStore = try? resetProfileUsage(
                store: newState.store,
                profileID: profileID
            ) {
                newState.store = updatedStore
                newState.measurementStates[profileID]?.usageBytes = ByteCount(0)
                newState.measurementStates[profileID]?.baseline = nil
                effects.append(.persistStore(updatedStore))
            }

        case let .changeLimit(profileID, newLimitBytes):
            if let updatedStore = try? updateProfileLimitBytes(
                store: newState.store,
                profileID: profileID,
                newLimitBytes: newLimitBytes
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
                if let profile = updatedStore.profiles.first(where: { $0.profileID == profileID }),
                   profile.protection.limitReached, !profile.protection.pauseBlocking,
                   let interfaceName = profile.interfaceName {
                    effects.append(.disassociate(interfaceName: interfaceName))
                }

            }

        case let .createOrUpdateProfile(alias, limitBytes, resetDay, interfaceName, ssidHex, bssid):
            let now = Date()
            let existing = newState.store.profiles.first {
                $0.interfaceName == interfaceName && $0.ssidHex == ssidHex
            }
            if let existing {
                let reached = existing.measurement.usageBytes.rawValue >= limitBytes.rawValue
                let updatedConfirmed = existing.confirmedBSSIDs.contains(bssid)
                    ? existing.confirmedBSSIDs
                    : existing.confirmedBSSIDs + [bssid]
                let updatedProtection = (try? existing.protection.updating(limitReached: reached)) ?? existing.protection
                if let updatedProfile = try? ProfileRecord(
                    profileID: existing.profileID,
                    aliasNFC: alias,
                    ssidHex: ssidHex,
                    interfaceName: interfaceName,
                    confirmedBSSIDs: updatedConfirmed,
                    isComplete: true,
                    sharesInterfaceSSID: existing.sharesInterfaceSSID,
                    limitBytes: limitBytes,
                    resetDay: resetDay,
                    cycle: existing.cycle,
                    measurement: existing.measurement,
                    protection: updatedProtection,
                    createdAt: existing.createdAt,
                    updatedAt: now
                ) {
                    let newProfiles = newState.store.profiles.map { $0.profileID == existing.profileID ? updatedProfile : $0 }
                    if let updatedStore = try? newState.store.updatingStore(now: now, selectedProfileID: existing.profileID, profiles: newProfiles) {
                        newState.store = updatedStore
                        if let resolved = newState.resolvedIdentity, resolved.interfaceName == interfaceName && resolved.ssid.hex == ssidHex {
                            newState.resolvedProfileID = existing.profileID
                            newState.connectionState = .monitoring
                        }
                        effects.append(.persistStore(updatedStore))
                    }
                }
            } else {
                let newProfileID = UUID()
                if let boundary = try? CycleCalculator.boundary(for: now, resetDay: Int(resetDay), timeZone: .current),
                   let cycle = try? CycleRecord(cycleID: boundary.id, wallClock: now),
                   let measurement = try? MeasurementRecord(
                       usageBytes: ByteCount(0),
                       baselinePending: true,
                       lastTrustedIdentity: nil,
                       lastRXBytes: nil,
                       lastTXBytes: nil,
                       lastSampleWallClock: nil,
                       lastPersistedUsageAt: now,
                       bytesSinceLastFlush: ByteCount(0)
                   ),
                   let retry = try? RetryRecord(state: .none, attemptIndex: 0, nextEligibleAt: nil, lastAttemptAt: nil),
                   let protection = try? ProtectionRecord(
                       limitReached: false,
                       pauseBlocking: false,
                       blockingCapability: .measurementOnly,
                       lastAuthorizationOutcome: .neverRequested,
                       retry: retry,
                       lastSuppressionObservation: nil,
                       lastFailureReason: nil,
                       ownedTransactionID: nil
                   ),
                   let newProfile = try? ProfileRecord(
                       profileID: newProfileID,
                       aliasNFC: alias,
                       ssidHex: ssidHex,
                       interfaceName: interfaceName,
                       confirmedBSSIDs: [bssid],
                       isComplete: true,
                       sharesInterfaceSSID: false,
                       limitBytes: limitBytes,
                       resetDay: resetDay,
                       cycle: cycle,
                       measurement: measurement,
                       protection: protection,
                       createdAt: now,
                       updatedAt: now
                   ) {
                    let newProfiles = newState.store.profiles + [newProfile]
                    if let updatedStore = try? newState.store.updatingStore(now: now, selectedProfileID: newProfileID, profiles: newProfiles) {
                        newState.store = updatedStore
                        newState.measurementStates[newProfileID] = MeasurementState(cycleID: boundary.id, usageBytes: ByteCount(0))
                        if let resolved = newState.resolvedIdentity, resolved.interfaceName == interfaceName && resolved.ssid.hex == ssidHex {
                            newState.resolvedProfileID = newProfileID
                            newState.connectionState = .monitoring
                        }
                        effects.append(.persistStore(updatedStore))
                    }
                }
            }

        case let .counterSampleIngested(sample):
            guard newState.store.globalState.safetyState == .normal, !sample.identity.ssid.hex.isEmpty else {
                break
            }
            let matchingProfile = newState.store.profiles.first { profile in
                profile.isComplete &&
                profile.interfaceName == sample.identity.interfaceName &&
                profile.ssidHex == sample.identity.ssid.hex &&
                profile.confirmedBSSIDs.contains(sample.identity.bssid)
            }
            guard let profile = matchingProfile else {
                break
            }
           let initialMeasurementState = newState.measurementStates[profile.profileID] ??
                MeasurementState(cycleID: sample.cycleID, usageBytes: profile.measurement.usageBytes)
           var accumulator = MeasurementAccumulator(initialState: initialMeasurementState)
           let outcome = accumulator.ingest(sample)
           newState.measurementStates[profile.profileID] = accumulator.state
           switch outcome {
            case let .usageAdded(_, persistence):
                let newUsage = accumulator.state.usageBytes
                let reached = newUsage.rawValue >= profile.limitBytes.rawValue
                let shouldFlushImmediately = (persistence == .requiredAndImmediate || reached)
                let bytesSinceLastFlush = shouldFlushImmediately ? ByteCount(0) : accumulator.state.bytesSinceLastFlush
               if let updatedStore = try? updateProfileUsageAndLimit(
                   store: newState.store,
                   profileID: profile.profileID,
                   newUsageBytes: newUsage,
                   limitReached: reached,
                   sample: sample,
                   bytesSinceLastFlush: bytesSinceLastFlush
               ) {
                   newState.store = updatedStore
                   if shouldFlushImmediately {
                       accumulator.markDurablyFlushed()
                       newState.measurementStates[profile.profileID] = accumulator.state
                       effects.append(.persistStore(updatedStore))
                   }
                    if reached && !profile.protection.pauseBlocking,
                       let interfaceName = profile.interfaceName {
                        effects.append(.disassociate(interfaceName: interfaceName))
                    }
               }
            case .recoveryRequired:
                if let updatedStore = try? updateGlobalSafety(
                    store: newState.store,
                    safety: .recoveryRequired,
                    recoveryReason: .arithmeticOverflow,
                    timeAdjustment: nil
                ) {
                    newState.store = updatedStore
                    effects.append(.persistStore(updatedStore))
                }
            case .baselineEstablished, .cycleChanged, .identityChanged, .counterRegression, .identityUnavailable:
                break
            }

        case let .selectProfile(profileID):
            if let updatedStore = try? updateSelectedProfile(
                store: newState.store,
                selectedProfileID: profileID
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case let .setLanguageOverride(override):
            if let updatedStore = try? updateLanguageOverride(
                store: newState.store,
                override: override
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }

        case let .muteFailureNotification(profileID, mute, expiresAt, cycleDate):
            if let updatedStore = try? updateNotificationMute(
                store: newState.store,
                profileID: profileID,
                mute: mute,
                expiresAt: expiresAt,
                cycleDate: cycleDate
            ) {
                newState.store = updatedStore
                effects.append(.persistStore(updatedStore))
            }
        }

        let snapshot = currentSnapshot(for: newState)
        effects.append(.emitSnapshot(snapshot))
        return (newState, effects)
    }

    public static func currentSnapshot(for state: RuntimeEngineState) -> RuntimeSnapshotV1 {
        let activeProfile = state.store.profiles.first { $0.profileID == (state.resolvedProfileID ?? state.store.selectedProfileID) }
        let selectedProfile = state.store.profiles.first { $0.profileID == state.store.selectedProfileID }
        let selectionState = RuntimeSnapshotV1.evaluateSelectionState(
            selectedID: state.store.selectedProfileID,
            connectedID: state.resolvedProfileID
        )
        let hasConflict = state.store.preferenceTransactions.contains { $0.phase == .conflict }
        let protectionState = RuntimeSnapshotV1.evaluateProtectionState(
            globalSafety: state.store.globalState.safetyState,
            profile: activeProfile,
            hasRestorationConflict: hasConflict,
            candidateLifecycle: state.candidateLifecycle
        )

        return RuntimeSnapshotV1(
            globalSafety: state.store.globalState.safetyState,
            connectionState: state.connectionState,
            selectionState: selectionState,
            protectionState: protectionState,
            candidateLifecycle: state.candidateLifecycle,
           connectedProfileID: state.resolvedProfileID,
           selectedProfileID: state.store.selectedProfileID,
           selectedProfileAlias: (activeProfile ?? selectedProfile)?.aliasNFC,
           isPauseBlockingActive: (activeProfile ?? selectedProfile)?.protection.pauseBlocking ?? false,
            currentUsageBytes: activeProfile?.measurement.usageBytes,
           currentLimitBytes: activeProfile?.limitBytes,
           cycleID: activeProfile?.cycle.cycleID,
            authorizationAvailable: state.authorizationAvailable,
            storeRevision: state.store.storeRevision,
            languageOverride: state.store.languageOverride,
            activeTransactionPhase: state.store.preferenceTransactions.first?.phase,
           recoveryReason: state.store.globalState.recoveryReason,
           timeAdjustmentReason: state.store.globalState.timeAdjustment?.reason
       )
   }

   private static func updateGlobalSafety(
       store: StoreEnvelopeV1,
       safety: GlobalSafetyState,
       recoveryReason: GlobalRecoveryReasonV1?,
       timeAdjustment: TimeAdjustmentRecord?
   ) throws -> StoreEnvelopeV1 {
       let newGlobalState = try GlobalStateRecord(
           safetyState: safety,
           recoveryReason: recoveryReason,
           timeAdjustment: timeAdjustment,
           counterCapability: store.globalState.counterCapability,
           identityCapability: store.globalState.identityCapability
       )
        return try store.updatingStore(globalState: newGlobalState)
   }

   private static func transitionProfileCycle(
       store: StoreEnvelopeV1,
       profileID: UUID,
       newCycleID: CycleID
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
           let newCycle = try CycleRecord(
               cycleID: newCycleID,
                wallClock: Date(),
                timeAcknowledgementRequired: false
           )
            let newMeasurement = try MeasurementRecord.initial(usageBytes: ByteCount(0))
            let newProtection = try profile.protection.updating(
               limitReached: false,
                retry: try RetryRecord(state: .none, attemptIndex: 0, nextEligibleAt: nil, lastAttemptAt: nil)
           )
            return try profile.updating(
               cycle: newCycle,
               measurement: newMeasurement,
                protection: newProtection
           )
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func updateProfileResetDay(
       store: StoreEnvelopeV1,
       profileID: UUID,
       newResetDay: UInt
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
            return try profile.updating(resetDay: newResetDay)
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func appendProfileBSSID(
       store: StoreEnvelopeV1,
       profileID: UUID,
       bssid: BSSID
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
           guard !profile.confirmedBSSIDs.contains(bssid) else { return profile }
           var newBSSIDs = profile.confirmedBSSIDs
           newBSSIDs.append(bssid)
            return try profile.updating(confirmedBSSIDs: newBSSIDs)
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func updateProfileLimitReached(
       store: StoreEnvelopeV1,
       profileID: UUID,
       reached: Bool
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
            let newProtection = try profile.protection.updating(limitReached: reached)
            return try profile.updating(protection: newProtection)
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func updateProfilePauseBlocking(
       store: StoreEnvelopeV1,
       profileID: UUID,
       isPaused: Bool
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
            let newProtection = try profile.protection.updating(pauseBlocking: isPaused)
            return try profile.updating(protection: newProtection)
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func resetProfileUsage(
       store: StoreEnvelopeV1,
       profileID: UUID
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
            let newMeasurement = try MeasurementRecord.initial(usageBytes: ByteCount(0))
            let newProtection = try profile.protection.updating(
               limitReached: false,
                retry: try RetryRecord(state: .none, attemptIndex: 0, nextEligibleAt: nil, lastAttemptAt: nil)
           )
            return try profile.updating(
               measurement: newMeasurement,
                protection: newProtection
           )
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func updateProfileLimitBytes(
       store: StoreEnvelopeV1,
       profileID: UUID,
       newLimitBytes: ByteCount
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
            let reached = profile.measurement.usageBytes.rawValue >= newLimitBytes.rawValue
            let newProtection = try profile.protection.updating(limitReached: reached)
            return try profile.updating(
                limitBytes: newLimitBytes,
                protection: newProtection
           )
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func updateProfileUsageAndLimit(
       store: StoreEnvelopeV1,
       profileID: UUID,
       newUsageBytes: ByteCount,
        limitReached: Bool,
        sample: MeasurementSample,
        bytesSinceLastFlush: ByteCount
   ) throws -> StoreEnvelopeV1 {
       let updatedProfiles = try store.profiles.map { profile -> ProfileRecord in
           guard profile.profileID == profileID else { return profile }
            let identitySnapshot = try IdentitySnapshotRecord(profileID: profileID, snapshot: sample.identity)
           let newMeasurement = try MeasurementRecord(
                usageBytes: newUsageBytes,
                baselinePending: false,
                lastTrustedIdentity: identitySnapshot,
                lastRXBytes: DecimalUInt64(rawValue: sample.counters.rx),
                lastTXBytes: DecimalUInt64(rawValue: sample.counters.tx),
                lastSampleWallClock: Date(),
                lastPersistedUsageAt: Date(),
                bytesSinceLastFlush: bytesSinceLastFlush
           )
             let eligibility = ProtectionEligibilityEvaluator.evaluate(ProtectionEligibilityInput(
                 globalSafety: store.globalState.safetyState,
                 compiledMode: BuildConfiguration.compiledMode,
                 identityCapability: store.globalState.identityCapability == .pending ? .passed : store.globalState.identityCapability,
                 counterCapability: store.globalState.counterCapability == .pending ? .passed : store.globalState.counterCapability,
                 sharedInterfaceSSID: profile.sharesInterfaceSSID,
                 authorizationAvailable: true,
                 exactTargetResolved: true,
                 pauseBlocking: profile.protection.pauseBlocking
             ))
             let newCapability: BlockingCapabilityV1 = switch eligibility {
                 case .strongBlockingReady: .strongReady
                 case .blockingNotGuaranteed(.measurementOnlyBuild): .measurementOnly
                 case .blockingNotGuaranteed(.sharedInterfaceSSID): .sharedInterfaceSSID
                 case .blockingNotGuaranteed(.authorizationUnavailable): .authorizationUnavailable
                 case .blockingNotGuaranteed: .notGuaranteed
                 case .recoveryRequired: .notGuaranteed
             }
             let newProtection = try profile.protection.updating(
                 limitReached: limitReached,
                 blockingCapability: newCapability
             )
            return try profile.updating(
               measurement: newMeasurement,
                protection: newProtection
           )
       }
        return try store.updatingStore(profiles: updatedProfiles)
   }

   private static func updateSelectedProfile(
       store: StoreEnvelopeV1,
       selectedProfileID: UUID?
   ) throws -> StoreEnvelopeV1 {
        try store.updatingStore(selectedProfileID: selectedProfileID)
   }

   private static func updateLanguageOverride(
       store: StoreEnvelopeV1,
       override: StoreLanguageOverrideV1
   ) throws -> StoreEnvelopeV1 {
        try store.updatingStore(languageOverride: override)
   }

   private static func updateNotificationMute(
       store: StoreEnvelopeV1,
       profileID: UUID,
       mute: ProfileFailureMuteV1,
       expiresAt: Date?,
       cycleDate: String?
   ) throws -> StoreEnvelopeV1 {
       var notifMap = store.notificationState.profileNotificationStates
       let existing = notifMap[profileID]
       let updatedRecord = try ProfileNotificationRecord(
           successNotifiedCycleDate: existing?.successNotifiedCycleDate,
           failureMute: mute,
           muteExpiresAt: expiresAt,
           muteCycleDate: cycleDate,
           lastFailureNotificationAt: existing?.lastFailureNotificationAt
       )
       notifMap[profileID] = updatedRecord
       let newNotificationState = NotificationStateRecord(
           profileNotificationStates: notifMap,
           systemAuthorization: store.notificationState.systemAuthorization
       )
        return try store.updatingStore(notificationState: newNotificationState)
   }
}
