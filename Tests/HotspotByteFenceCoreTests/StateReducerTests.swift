import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class StateReducerTests: XCTestCase {
    private let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let bssid1 = try! BSSID(string: "00:11:22:33:44:55")
    private let bssid2 = try! BSSID(string: "AA:BB:CC:DD:EE:FF")
    private let ssidHex = "486f7473706f74"

    func testConnectionSelectsRegisteredProfileOnlyWhenConnectionChanges() throws {
        var state = try makeInitialState()
        let otherID = UUID()
        let other = try makeProfile(profileID: otherID, networkSSIDHex: "4f74686572")
        state.store = try state.store.updatingStore(
            selectedProfileID: otherID, profiles: state.store.profiles + [other]
        )
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0", interfaceIndex: 1, linkState: .associated,
            ssid: try SSID(hex: ssidHex), bssid: bssid1
        )
        let (connected, effects) = StateReducer.reduce(state: state, event: .networkResolutionChanged(identity: identity))
        XCTAssertEqual(connected.store.selectedProfileID, profileID)
        XCTAssertTrue(effects.contains { if case .persistStore = $0 { return true }; return false })

        let otherIdentity = WiFiIdentitySnapshot(
            interfaceName: "en0", interfaceIndex: 1, linkState: .associated,
            ssid: try SSID(hex: "4f74686572"), bssid: bssid1
        )
        let (switched, _) = StateReducer.reduce(state: connected, event: .networkResolutionChanged(identity: otherIdentity))
        XCTAssertEqual(switched.store.selectedProfileID, otherID)
        XCTAssertEqual(switched.resolvedProfileID, otherID)

        let (selected, _) = StateReducer.reduce(state: connected, event: .selectProfile(profileID: otherID))
        let (repeated, repeatedEffects) = StateReducer.reduce(state: selected, event: .networkResolutionChanged(identity: identity))
        XCTAssertEqual(repeated.store.selectedProfileID, otherID)
        XCTAssertFalse(repeatedEffects.contains { if case .persistStore = $0 { return true }; return false })

        let (disconnected, _) = StateReducer.reduce(state: repeated, event: .networkResolutionChanged(identity: nil))
        let (reconnected, _) = StateReducer.reduce(state: disconnected, event: .networkResolutionChanged(identity: identity))
        XCTAssertEqual(reconnected.store.selectedProfileID, profileID)
    }

    func testChangedBSSIDApprovalPreservesUsageAndResumesMonitoring() throws {
        var state = try makeInitialState()
        let profile = try state.store.profiles[0].updating(
            measurement: MeasurementRecord.initial(usageBytes: ByteCount(1_710_000_000))
        )
        state.store = try state.store.updatingStore(profiles: [profile])
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0", interfaceIndex: 1, linkState: .associated,
            ssid: try SSID(hex: ssidHex), bssid: bssid2
        )
        let (pending, _) = StateReducer.reduce(state: state, event: .networkResolutionChanged(identity: identity))
        let (staleApproval, _) = StateReducer.reduce(state: pending, event: .confirmBSSID(profileID: profileID, bssid: bssid1))
        XCTAssertEqual(staleApproval.connectionState, .needsBSSIDConfirmation)
        XCTAssertEqual(staleApproval.store.profiles[0], profile)
        let (disconnected, _) = StateReducer.reduce(state: pending, event: .networkResolutionChanged(identity: nil))
        let (cancelled, _) = StateReducer.reduce(state: disconnected, event: .confirmBSSID(profileID: profileID, bssid: bssid2))
        XCTAssertEqual(cancelled.store.profiles[0], profile)
        let (confirmed, _) = StateReducer.reduce(state: pending, event: .confirmBSSID(profileID: profileID, bssid: bssid2))
        XCTAssertNil(pending.resolvedProfileID)
        XCTAssertEqual(confirmed.resolvedProfileID, profileID)
        XCTAssertEqual(confirmed.connectionState, .monitoring)
        XCTAssertEqual(confirmed.store.profiles.count, 1)
        XCTAssertEqual(confirmed.store.profiles[0].measurement.usageBytes, ByteCount(1_710_000_000))
        XCTAssertEqual(confirmed.store.profiles[0].limitBytes, profile.limitBytes)
        let (reconnected, _) = StateReducer.reduce(state: confirmed, event: .networkResolutionChanged(identity: identity))
        XCTAssertEqual(reconnected.connectionState, .monitoring)
    }

    func testGlobalSafetyTransitionsAndEffects() throws {
        let state = try makeInitialState()

        let (state1, effects1) = StateReducer.reduce(
            state: state,
            event: .storeFailure(.corruptStore)
        )
        XCTAssertEqual(state1.store.globalState.safetyState, GlobalSafetyState.recoveryRequired)
        XCTAssertEqual(state1.store.globalState.recoveryReason, GlobalRecoveryReasonV1.corruptStore)
        XCTAssertTrue(effects1.contains(where: {
            if case .persistStore = $0 { return true } else { return false }
        }))
        XCTAssertTrue(effects1.contains(where: {
            if case let .emitSnapshot(s) = $0 { return s.globalSafety == GlobalSafetyState.recoveryRequired } else { return false }
        }))

        let (state2, effects2) = StateReducer.reduce(
            state: state,
            event: .arithmeticOverflow
        )
        XCTAssertEqual(state2.store.globalState.safetyState, GlobalSafetyState.recoveryRequired)
        XCTAssertEqual(state2.store.globalState.recoveryReason, GlobalRecoveryReasonV1.arithmeticOverflow)
        XCTAssertTrue(effects2.contains(where: {
            if case .persistStore = $0 { return true } else { return false }
        }))

        let (state3, effects3) = StateReducer.reduce(
            state: state,
            event: .counterDeterministicFailure
        )
        XCTAssertEqual(state3.store.globalState.safetyState, GlobalSafetyState.recoveryRequired)
        XCTAssertEqual(state3.store.globalState.recoveryReason, GlobalRecoveryReasonV1.counterCapabilityFailure)
        XCTAssertTrue(effects3.contains(where: {
            if case .persistStore = $0 { return true } else { return false }
        }))

        let (state4, effects4) = StateReducer.reduce(
            state: state,
            event: .backwardWallClockDetected(trustedCycleDate: "2026-09-01", observedCycleDate: "2026-08-31", timeZoneID: "Asia/Seoul")
        )
        XCTAssertEqual(state4.store.globalState.safetyState, GlobalSafetyState.timeAdjustmentRequired)
        XCTAssertEqual(state4.store.globalState.timeAdjustment?.reason, TimeAdjustmentReasonV1.backwardWallClock)
        XCTAssertTrue(effects4.contains(where: {
            if case .persistStore = $0 { return true } else { return false }
        }))

        let (state5, _) = StateReducer.reduce(
            state: state,
            event: .divergenceDetected(trustedCycleDate: "2026-09-01", observedCycleDate: "2026-09-02", timeZoneID: "Asia/Seoul")
        )
        XCTAssertEqual(state5.store.globalState.safetyState, GlobalSafetyState.timeAdjustmentRequired)
        XCTAssertEqual(state5.store.globalState.timeAdjustment?.reason, TimeAdjustmentReasonV1.wallMonotonicDivergence)

        let (state6, effects6) = StateReducer.reduce(
            state: state5,
            event: .acknowledgeTimeAdjustment
        )
        XCTAssertEqual(state6.store.globalState.safetyState, GlobalSafetyState.normal)
        XCTAssertNil(state6.store.globalState.timeAdjustment)
        XCTAssertTrue(effects6.contains(where: {
            if case .persistStore = $0 { return true } else { return false }
        }))
    }

    func testSleepWakeAndQuitLifecycle() throws {
        var state = try makeInitialState()
        let cycleID = CycleID(effectiveDate: "2026-09-01", timeZoneID: "Asia/Seoul")
        state.connectionState = .monitoring
        var measurementState = MeasurementState(cycleID: cycleID, usageBytes: ByteCount(100))
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: ssidHex),
            bssid: bssid1
        )
        measurementState.baseline = MeasurementBaseline(
            identity: identity,
            counters: CounterSnapshot(rx: 50, tx: 50),
            cycleID: cycleID
        )
        state.measurementStates[profileID] = measurementState

        let ssidBytes = try SSID(hex: ssidHex).bytes
        let tracker = WiFiObservationWindowTracker(
            processLifecycleID: UUID(),
            targetInterfaceName: "en0",
            targetSSIDBytes: ssidBytes,
            targetBSSID: bssid1.description,
            startNanoseconds: 1_000_000
        )
        state.activeObservationTracker = tracker

        let (sleepState, _) = StateReducer.reduce(state: state, event: .sleepOccurred)
        XCTAssertEqual(sleepState.connectionState, ConnectionState.disconnected)
        XCTAssertNil(sleepState.measurementStates[profileID]?.baseline)
        XCTAssertTrue(sleepState.activeObservationTracker?.isInterrupted == true)

        let (wakeState, _) = StateReducer.reduce(state: sleepState, event: .wakeOccurred(monotonicNanoseconds: 123456789))
        XCTAssertEqual(wakeState.lastAwakeTimestampNanoseconds, 123456789)
        XCTAssertNil(wakeState.measurementStates[profileID]?.baseline)

        let activeTracker = WiFiObservationWindowTracker(
            processLifecycleID: UUID(),
            targetInterfaceName: "en0",
            targetSSIDBytes: ssidBytes,
            targetBSSID: bssid1.description,
            startNanoseconds: 2_000_000
        )
        var quitTargetState = state
        quitTargetState.activeObservationTracker = activeTracker
        let (quitState, _) = StateReducer.reduce(state: quitTargetState, event: .voluntaryQuitRequested)
        XCTAssertTrue(quitState.activeObservationTracker?.isInterrupted == true)
    }

    func testNetworkResolutionAndBSSIDConfirmation() throws {
        let state = try makeInitialState()

        let (permState, _) = StateReducer.reduce(state: state, event: .locationPermissionChanged(isAvailable: false))
        XCTAssertEqual(permState.connectionState, ConnectionState.locationPermissionRequired)
        XCTAssertNil(permState.resolvedIdentity)
        XCTAssertNil(permState.resolvedProfileID)

        let (discState, _) = StateReducer.reduce(state: state, event: .networkResolutionChanged(identity: nil))
        XCTAssertEqual(discState.connectionState, ConnectionState.disconnected)
        XCTAssertNil(discState.resolvedIdentity)

        let unknownIdentity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: "9999"),
            bssid: bssid1
        )
        let (unknownState, _) = StateReducer.reduce(state: state, event: .networkResolutionChanged(identity: unknownIdentity))
        XCTAssertEqual(unknownState.connectionState, ConnectionState.unknownNetwork)
        XCTAssertNil(unknownState.resolvedProfileID)

        let unconfirmedBSSIDIdentity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: ssidHex),
            bssid: bssid2
        )
        let (needsConfirmState, _) = StateReducer.reduce(state: state, event: .networkResolutionChanged(identity: unconfirmedBSSIDIdentity))
        XCTAssertEqual(needsConfirmState.connectionState, ConnectionState.needsBSSIDConfirmation)
        XCTAssertNil(needsConfirmState.resolvedProfileID)

        let (confirmedState, confirmedEffects) = StateReducer.reduce(
            state: needsConfirmState,
            event: .confirmBSSID(profileID: profileID, bssid: bssid2)
        )
        XCTAssertEqual(confirmedState.connectionState, ConnectionState.monitoring)
        XCTAssertEqual(confirmedState.resolvedProfileID, profileID)
        XCTAssertEqual(confirmedState.store.selectedProfileID, profileID)
        let updatedProfile = confirmedState.store.profiles.first { $0.profileID == profileID }
        XCTAssertTrue(updatedProfile?.confirmedBSSIDs.contains(bssid2) == true)
        XCTAssertTrue(confirmedEffects.contains(where: {
            if case .persistStore = $0 { return true } else { return false }
        }))

        let confirmedIdentity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: ssidHex),
            bssid: bssid1
        )
        let (monState, _) = StateReducer.reduce(state: state, event: .networkResolutionChanged(identity: confirmedIdentity))
        XCTAssertEqual(monState.connectionState, ConnectionState.monitoring)
        XCTAssertEqual(monState.resolvedProfileID, profileID)
    }

    func testCounterSampleIngestionAndFlushThreshold() throws {
        let state = try makeInitialState()
        let cycleID = CycleID(effectiveDate: "2026-09-01", timeZoneID: "Asia/Seoul")
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: ssidHex),
            bssid: bssid1
        )

        let sample1 = MeasurementSample(
            identity: identity,
            counters: CounterSnapshot(rx: 1_000_000, tx: 1_000_000),
            cycleID: cycleID
        )
        let (state1, effects1) = StateReducer.reduce(state: state, event: .counterSampleIngested(sample: sample1))
        XCTAssertEqual(state1.measurementStates[profileID]?.usageBytes, ByteCount(0))
        XCTAssertFalse(effects1.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let sample2 = MeasurementSample(
            identity: identity,
            counters: CounterSnapshot(rx: 3_500_000, tx: 3_500_000),
            cycleID: cycleID
        )
        let (state2, effects2) = StateReducer.reduce(state: state1, event: .counterSampleIngested(sample: sample2))
        XCTAssertEqual(state2.measurementStates[profileID]?.usageBytes, ByteCount(5_000_000))
        XCTAssertFalse(effects2.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let sample3 = MeasurementSample(
            identity: identity,
            counters: CounterSnapshot(rx: 6_500_000, tx: 6_500_000),
            cycleID: cycleID
        )
        let (state3, effects3) = StateReducer.reduce(state: state2, event: .counterSampleIngested(sample: sample3))
        XCTAssertEqual(state3.measurementStates[profileID]?.usageBytes, ByteCount(11_000_000))
        XCTAssertTrue(effects3.contains(where: { if case .persistStore = $0 { return true } else { return false } }))
        XCTAssertEqual(state3.measurementStates[profileID]?.bytesSinceLastFlush, ByteCount(0))

        let sample4 = MeasurementSample(
            identity: identity,
            counters: CounterSnapshot(rx: 60_000_000, tx: 60_000_000),
            cycleID: cycleID
        )
        let (state4, effects4) = StateReducer.reduce(state: state3, event: .counterSampleIngested(sample: sample4))
        let profile4 = state4.store.profiles.first { $0.profileID == profileID }
        XCTAssertTrue(profile4?.protection.limitReached == true)
        XCTAssertTrue(effects4.contains(where: { if case .persistStore = $0 { return true } else { return false } }))
    }

    func testProfileManagementEvents() throws {
        let state = try makeInitialState()
        let newCycleID = CycleID(effectiveDate: "2026-10-01", timeZoneID: "Asia/Seoul")

        let (cycleState, cycleEffects) = StateReducer.reduce(
            state: state,
            event: .forwardCycleTransition(profileID: profileID, newCycleID: newCycleID)
        )
        let cycleProfile = cycleState.store.profiles.first { $0.profileID == profileID }
        XCTAssertEqual(cycleProfile?.cycle.cycleID, newCycleID)
        XCTAssertEqual(cycleProfile?.measurement.usageBytes, ByteCount(0))
        XCTAssertEqual(cycleProfile?.protection.limitReached, false)
        XCTAssertTrue(cycleEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let (resetState, resetEffects) = StateReducer.reduce(
            state: state,
            event: .changeResetDay(profileID: profileID, newResetDay: 15)
        )
        XCTAssertEqual(resetState.store.profiles.first { $0.profileID == profileID }?.resetDay, 15)
        XCTAssertTrue(resetEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let (pauseState, pauseEffects) = StateReducer.reduce(
            state: state,
            event: .pauseBlockingToggled(profileID: profileID, isPaused: true)
        )
        XCTAssertEqual(pauseState.store.profiles.first { $0.profileID == profileID }?.protection.pauseBlocking, true)
        XCTAssertTrue(pauseEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let (resetUsageState, resetUsageEffects) = StateReducer.reduce(
            state: state,
            event: .manualResetUsage(profileID: profileID)
        )
        XCTAssertEqual(resetUsageState.store.profiles.first { $0.profileID == profileID }?.measurement.usageBytes, ByteCount(0))
        XCTAssertTrue(resetUsageEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let (limitState, limitEffects) = StateReducer.reduce(
            state: state,
            event: .changeLimit(profileID: profileID, newLimitBytes: ByteCount(500_000_000))
        )
        XCTAssertEqual(limitState.store.profiles.first { $0.profileID == profileID }?.limitBytes, ByteCount(500_000_000))
        XCTAssertTrue(limitEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let editedAlias = "Other Profile"
        let (editedState, editedEffects) = StateReducer.reduce(
            state: state,
            event: .editProfile(
                profileID: profileID,
                alias: editedAlias,
                limitBytes: ByteCount(ProfileRecord.maximumLimitBytes),
                resetDay: 21
            )
        )
        let editedProfile = editedState.store.profiles.first { $0.profileID == profileID }
        XCTAssertEqual(editedProfile?.aliasNFC, editedAlias)
        XCTAssertEqual(editedProfile?.limitBytes.rawValue, ProfileRecord.maximumLimitBytes)
        XCTAssertEqual(editedProfile?.resetDay, 21)
        XCTAssertTrue(editedEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let otherProfileID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let otherProfile = try makeProfile(profileID: otherProfileID, networkSSIDHex: "4f74686572")
        let otherSelectedStore = try state.store.updatingStore(
            selectedProfileID: otherProfileID,
            profiles: [state.store.profiles[0], otherProfile]
        )
        let otherSelectedState = RuntimeEngineState(store: otherSelectedStore)
        let (editedOtherState, _) = StateReducer.reduce(
            state: otherSelectedState,
            event: .editProfile(
                profileID: profileID,
                alias: "Edited While Other Is Selected",
                limitBytes: ByteCount(200_000_000),
                resetDay: 22
            )
        )
        XCTAssertEqual(editedOtherState.store.selectedProfileID, otherProfileID)
        XCTAssertEqual(
            editedOtherState.store.profiles.first { $0.profileID == profileID }?.aliasNFC,
            "Edited While Other Is Selected"
        )
        XCTAssertEqual(
            editedOtherState.store.profiles.first { $0.profileID == otherProfileID }?.aliasNFC,
            otherProfile.aliasNFC
        )

        let (selState, selEffects) = StateReducer.reduce(
            state: state,
            event: .selectProfile(profileID: profileID)
        )
        XCTAssertEqual(selState.store.selectedProfileID, profileID)
        XCTAssertTrue(selEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let (langState, langEffects) = StateReducer.reduce(
            state: state,
            event: .setLanguageOverride(.en)
        )
        XCTAssertEqual(langState.store.languageOverride, StoreLanguageOverrideV1.en)
        XCTAssertTrue(langEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))

        let (muteState, muteEffects) = StateReducer.reduce(
            state: state,
            event: .muteFailureNotification(
                profileID: profileID,
                mute: .untilCycleEnds,
                expiresAt: nil,
                cycleDate: "2026-09-01"
            )
        )
        let muteRecord = muteState.store.notificationState.profileNotificationStates[profileID]
        XCTAssertEqual(muteRecord?.failureMute, ProfileFailureMuteV1.untilCycleEnds)
        XCTAssertEqual(muteRecord?.muteCycleDate, "2026-09-01")
        XCTAssertTrue(muteEffects.contains(where: { if case .persistStore = $0 { return true } else { return false } }))
    }

    func testProfileLimitEditRequestsDisassociateUnlessBlockingIsPaused() throws {
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: ssidHex),
            bssid: bssid1
        )
        var state = try makeInitialState()
        let profile = state.store.profiles[0]
        let overLimitMeasurement = try MeasurementRecord.initial(usageBytes: ByteCount(200_000_000))
        state.store = try state.store.updatingStore(profiles: [try profile.updating(measurement: overLimitMeasurement)])
        state.resolvedIdentity = identity
        state.resolvedProfileID = profileID
        state.connectionState = .monitoring

        let (_, effects) = StateReducer.reduce(
            state: state,
            event: .createOrUpdateProfile(
                alias: "Edited Hotspot",
                limitBytes: ByteCount(100_000_000),
                resetDay: 1,
                interfaceName: "en0",
                ssidHex: ssidHex,
                bssid: bssid1
            )
        )
        XCTAssertTrue(effects.contains(.disassociate(interfaceName: "en0")))

        let (pausedState, _) = StateReducer.reduce(
            state: state,
            event: .pauseBlockingToggled(profileID: profileID, isPaused: true)
        )
        let (_, pausedEffects) = StateReducer.reduce(
            state: pausedState,
            event: .createOrUpdateProfile(
                alias: "Edited Hotspot",
                limitBytes: ByteCount(100_000_000),
                resetDay: 1,
                interfaceName: "en0",
                ssidHex: ssidHex,
                bssid: bssid1
            )
        )
        XCTAssertFalse(pausedEffects.contains(.disassociate(interfaceName: "en0")))
    }

    private func makeInitialState() throws -> RuntimeEngineState {
        let envelope = try makeEnvelope()
        return RuntimeEngineState(store: envelope)
    }

    private func makeEnvelope() throws -> StoreEnvelopeV1 {
        let profile = try makeProfile(profileID: profileID)
        let revision = DecimalUInt64(rawValue: 1)
        return try StoreEnvelopeV1(
            storeRevision: revision,
            previousGoodRevision: nil,
            installationID: UUID(),
            hasCompletedProfile: true,
            observedArtifact: try makeArtifactObservation(),
            globalState: try GlobalStateRecord(
                safetyState: .normal,
                recoveryReason: nil,
                timeAdjustment: nil,
                counterCapability: .pending,
                identityCapability: .pending
            ),
            selectedProfileID: nil,
            languageOverride: .ko,
            profiles: [profile],
            preferenceTransactions: [],
            commandResults: [],
            notificationState: NotificationStateRecord(),
            eventLog: try EventLogRecord(),
            tombstoneDigest: String(repeating: "0", count: 64),
            integrity: try IntegrityRecord(
                canonicalDigest: String(repeating: "a", count: 64),
                lkgDigest: nil,
                lastValidatedRevision: revision,
                previousValidatedRevision: nil,
                validatedAt: Date(timeIntervalSince1970: 20)
            )
        )
    }

    private func makeProfile(profileID: UUID, networkSSIDHex: String? = nil) throws -> ProfileRecord {
        try ProfileRecord(
            profileID: profileID,
            aliasNFC: networkSSIDHex == nil ? "My Hotspot" : "Other Hotspot",
            ssidHex: networkSSIDHex ?? ssidHex,
            interfaceName: "en0",
            confirmedBSSIDs: [bssid1],
            isComplete: true,
            sharesInterfaceSSID: false,
            limitBytes: ByteCount(100_000_000),
            resetDay: 1,
            cycle: try CycleRecord(
                cycleID: CycleID(effectiveDate: "2026-09-01", timeZoneID: "Asia/Seoul"),
                wallClock: Date(timeIntervalSince1970: 1),
                timeAcknowledgementRequired: false
            ),
            measurement: try MeasurementRecord(
                usageBytes: ByteCount(0),
                baselinePending: true,
                lastTrustedIdentity: nil,
                lastRXBytes: nil,
                lastTXBytes: nil,
                lastSampleWallClock: nil,
                lastPersistedUsageAt: Date(timeIntervalSince1970: 10),
                bytesSinceLastFlush: ByteCount(0)
            ),
            protection: try ProtectionRecord(
                limitReached: false,
                pauseBlocking: false,
                blockingCapability: .measurementOnly,
                lastAuthorizationOutcome: .neverRequested,
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
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeArtifactObservation() throws -> ArtifactObservationRecord {
        try ArtifactObservationRecord(
            compiledModeObserved: .measurementOnly,
            buildManifestSHA256: String(repeating: "0", count: 64),
            codeSignatureStatus: .unsigned,
            hardenedRuntimeStatus: .unavailable,
            notarizationStatus: .notApplicable,
            gatekeeperStatus: .notApplicable,
            quarantineStatus: .absent,
            macOSBuild: "24A335",
            observedAt: Date(timeIntervalSince1970: 10)
        )
    }
}
