import Foundation

public actor RuntimeEngine {
    public private(set) var state: RuntimeEngineState
    private let store: EnvelopeStoreProtocol
    private let counterSource: InterfaceCounterSource
    private let identitySource: WiFiIdentitySource
    private let clock: ClockProtocol
    private let calendar: Calendar
    private let timeZone: TimeZone

    private var periodicPollingTask: Task<Void, Never>?
    private let snapshotContinuation: AsyncStream<RuntimeSnapshotV1>.Continuation
    public nonisolated let snapshots: AsyncStream<RuntimeSnapshotV1>

    public init(
        store: EnvelopeStoreProtocol,
        initialEnvelope: StoreEnvelopeV1,
        counterSource: InterfaceCounterSource,
        identitySource: WiFiIdentitySource,
        clock: ClockProtocol = SystemClock(),
        candidateLifecycle: CandidateLifecycle = .production,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current
    ) {
        self.store = store
        self.counterSource = counterSource
        self.identitySource = identitySource
        self.clock = clock
        self.calendar = calendar
        self.timeZone = timeZone

        let (stream, continuation) = AsyncStream.makeStream(of: RuntimeSnapshotV1.self)
        self.snapshots = stream
        self.snapshotContinuation = continuation

        var measurementStates: [UUID: MeasurementState] = [:]
        for profile in initialEnvelope.profiles {
            measurementStates[profile.profileID] = MeasurementState(
                cycleID: profile.cycle.cycleID,
                usageBytes: profile.measurement.usageBytes
            )
        }

        self.state = RuntimeEngineState(
            store: initialEnvelope,
            candidateLifecycle: candidateLifecycle,
            processLifecycleID: UUID(),
            authorizationAvailable: false,
            resolvedIdentity: nil,
            connectionState: .disconnected,
            resolvedProfileID: nil,
            measurementStates: measurementStates,
            activeObservationTracker: nil,
            manualReconnectTokenExpiresAt: nil,
            lastAwakeTimestampNanoseconds: clock.monotonicNanoseconds()
        )
    }

    deinit {
        periodicPollingTask?.cancel()
        snapshotContinuation.finish()
    }

    public func currentSnapshot() -> RuntimeSnapshotV1 {
        StateReducer.currentSnapshot(for: state)
    }

    public func currentResolvedIdentity() -> WiFiIdentitySnapshot? {
        state.resolvedIdentity
    }

    public func currentStore() -> StoreEnvelopeV1 {
        state.store
    }

    @discardableResult
    public func handle(event: RuntimeEvent) async throws -> RuntimeSnapshotV1 {
        let (newState, effects) = StateReducer.reduce(state: state, event: event)
        self.state = newState

        for effect in effects {
            try await applySideEffect(effect)
        }

        let snapshot = StateReducer.currentSnapshot(for: self.state)
        snapshotContinuation.yield(snapshot)
        return snapshot
    }

    public func performPeriodicTick() async throws -> RuntimeSnapshotV1 {
        if state.store.globalState.safetyState == .recoveryRequired ||
           state.store.globalState.safetyState == .timeAdjustmentRequired {
            return currentSnapshot()
        }

        let observations: [WiFiIdentityObservation]
        do {
            observations = try identitySource.readAll()
        } catch {
            return try await handle(event: .networkResolutionChanged(identity: nil))
        }

        let associated = observations.compactMap { observation -> WiFiIdentitySnapshot? in
            if case let .associated(snapshot) = observation {
                return snapshot
            }
            return nil
        }

        guard let primarySnapshot = associated.first else {
            return try await handle(event: .networkResolutionChanged(identity: nil))
        }

        try await handle(event: .networkResolutionChanged(identity: primarySnapshot))

        guard let resolvedProfileID = state.resolvedProfileID,
              let profile = state.store.profiles.first(where: { $0.profileID == resolvedProfileID }),
              state.connectionState == .monitoring else {
            return currentSnapshot()
        }

        let boundary: CycleBoundary
        do {
            boundary = try CycleCalculator.boundary(
                for: clock.now(),
                resetDay: Int(profile.resetDay),
                timeZone: timeZone
            )
        } catch {
            return currentSnapshot()
        }

        if boundary.id != profile.cycle.cycleID {
            let trustedDate = profile.cycle.cycleID.effectiveDate
            let observedDate = boundary.effectiveDate
            if observedDate < trustedDate {
                return try await handle(event: .backwardWallClockDetected(
                    trustedCycleDate: trustedDate,
                    observedCycleDate: observedDate,
                    timeZoneID: timeZone.identifier
                ))
            } else {
                try await handle(event: .forwardCycleTransition(
                    profileID: profile.profileID,
                    newCycleID: boundary.id
                ))
            }
        }

        let counters: InterfaceCounters
        do {
            counters = try counterSource.read(interfaceName: primarySnapshot.interfaceName)
        } catch {
            return currentSnapshot()
        }

        let sample = MeasurementSample(
            identity: primarySnapshot,
            counters: CounterSnapshot(rx: counters.rx, tx: counters.tx),
            cycleID: profile.cycle.cycleID
        )
        return try await handle(event: .counterSampleIngested(sample: sample))
    }

    public func startPeriodicPolling(intervalSeconds: TimeInterval = 5.0) {
        stopPeriodicPolling()
        periodicPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
                } catch {
                    break
                }
                guard let self else { break }
                _ = try? await self.performPeriodicTick()
            }
        }
    }

    public func stopPeriodicPolling() {
        periodicPollingTask?.cancel()
        periodicPollingTask = nil
    }

    @discardableResult
    public func sleep() async throws -> RuntimeSnapshotV1 {
        try await handle(event: .sleepOccurred)
    }

    @discardableResult
    public func wake() async throws -> RuntimeSnapshotV1 {
        try await handle(event: .wakeOccurred(monotonicNanoseconds: clock.monotonicNanoseconds()))
    }

    @discardableResult
    public func voluntaryQuit() async throws -> RuntimeSnapshotV1 {
        stopPeriodicPolling()
        return try await handle(event: .voluntaryQuitRequested)
    }

   @discardableResult
   public func selectProfile(id: UUID?) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .selectProfile(profileID: id))
   }

    @discardableResult
    public func changeLimit(profileID: UUID, newLimitBytes: ByteCount) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .changeLimit(profileID: profileID, newLimitBytes: newLimitBytes))
    }

    @discardableResult
    public func createOrUpdateProfile(
        alias: String,
        limitBytes: ByteCount,
        resetDay: UInt,
        interfaceName: String,
        ssidHex: String,
        bssid: BSSID
    ) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .createOrUpdateProfile(
            alias: alias,
            limitBytes: limitBytes,
            resetDay: resetDay,
            interfaceName: interfaceName,
            ssidHex: ssidHex,
            bssid: bssid
        ))
    }

    @discardableResult
    public func changeResetDay(profileID: UUID, newResetDay: UInt) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .changeResetDay(profileID: profileID, newResetDay: newResetDay))
    }

    @discardableResult
    public func manualResetUsage(profileID: UUID) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .manualResetUsage(profileID: profileID))
    }

    @discardableResult
    public func pauseBlockingToggled(profileID: UUID, isPaused: Bool) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .pauseBlockingToggled(profileID: profileID, isPaused: isPaused))
    }

    @discardableResult
    public func confirmBSSID(profileID: UUID, bssid: BSSID) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .confirmBSSID(profileID: profileID, bssid: bssid))
    }

    @discardableResult
    public func setLanguageOverride(_ override: StoreLanguageOverrideV1) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .setLanguageOverride(override))
    }

    @discardableResult
    public func setAuthorizationAvailable(_ available: Bool) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .authorizationChanged(isAvailable: available))
    }

    @discardableResult
    public func setLocationPermissionAvailable(_ available: Bool) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .locationPermissionChanged(isAvailable: available))
    }

    @discardableResult
    public func acknowledgeTimeAdjustment() async throws -> RuntimeSnapshotV1 {
        try await handle(event: .acknowledgeTimeAdjustment)
    }

    @discardableResult
    public func muteFailureNotification(
        profileID: UUID,
        mute: ProfileFailureMuteV1,
        expiresAt: Date?,
        cycleDate: String?
    ) async throws -> RuntimeSnapshotV1 {
        try await handle(event: .muteFailureNotification(
            profileID: profileID,
            mute: mute,
            expiresAt: expiresAt,
            cycleDate: cycleDate
        ))
    }

    public func flush() throws {
        let op: JournalOperation = state.store.profiles.contains(where: { $0.protection.limitReached })
            ? .limitReached
            : .measurementSample
        try store.commitEnvelope(state.store, operation: op)
    }

    private func applySideEffect(_ effect: RuntimeSideEffect) async throws {
        switch effect {
        case let .persistStore(envelope):
            do {
                let op: JournalOperation = envelope.profiles.contains(where: { $0.protection.limitReached })
                    ? .limitReached
                    : .measurementSample
                try store.commitEnvelope(envelope, operation: op)
            } catch {
                let (recoveryState, _) = StateReducer.reduce(state: state, event: .storeFailure(.writeFailure))
                self.state = recoveryState
                throw error
            }
        case let .emitSnapshot(snapshot):
            snapshotContinuation.yield(snapshot)
        case .disassociate:
            break
        case .requestAuthorization:
            break
        case .scheduleEnforcementRetry:
            break
        }
    }
}

#if canImport(Darwin) && canImport(CoreWLAN)
public extension RuntimeEngine {
    init(
        store: EnvelopeStoreProtocol,
        initialEnvelope: StoreEnvelopeV1,
        clock: ClockProtocol = SystemClock(),
        candidateLifecycle: CandidateLifecycle = .production,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current
    ) {
        self.init(
            store: store,
            initialEnvelope: initialEnvelope,
            counterSource: DarwinInterfaceCounterSource(),
            identitySource: CoreWLANIdentityAdapter(),
            clock: clock,
            candidateLifecycle: candidateLifecycle,
            calendar: calendar,
            timeZone: timeZone
        )
    }
}
#endif
