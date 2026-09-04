import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class RuntimeEngineTests: XCTestCase {
    private let profileID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let bssid1 = try! BSSID(string: "00:11:22:33:44:55")
    private let ssidHex = "486f7473706f74"
    private let timeZone = TimeZone(identifier: "Asia/Seoul")!

    func testInitialization() async throws {
        let (engine, _, _, _, _) = try makeEngine()
        let snapshot = await engine.currentSnapshot()

        XCTAssertEqual(snapshot.globalSafety, GlobalSafetyState.normal)
        XCTAssertEqual(snapshot.connectionState, ConnectionState.disconnected)
        XCTAssertNil(snapshot.connectedProfileID)
        let profileCount = await engine.state.store.profiles.count
        XCTAssertEqual(profileCount, 1)
    }

    func testPerformPeriodicTickAssociatesAndIngestsCounters() async throws {
        let (engine, store, counterSource, identitySource, clock) = try makeEngine()

        let ssid = try SSID(hex: ssidHex)
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: ssid,
            bssid: bssid1
        )
        identitySource.setObservations([.associated(identity)])
        counterSource.setCounters(interfaceName: "en0", counters: InterfaceCounters(rx: 1_000_000, tx: 1_000_000, total: 2_000_000))

        let snapshot1 = try await engine.performPeriodicTick()
        XCTAssertEqual(snapshot1.connectionState, ConnectionState.monitoring)
        XCTAssertEqual(snapshot1.connectedProfileID, profileID)
        XCTAssertEqual(snapshot1.currentUsageBytes, ByteCount(0))

        counterSource.setCounters(interfaceName: "en0", counters: InterfaceCounters(rx: 1_500_000, tx: 1_500_000, total: 3_000_000))
        let snapshot2 = try await engine.performPeriodicTick()
        XCTAssertEqual(snapshot2.currentUsageBytes, ByteCount(1_000_000))
        _ = clock
        _ = store
    }

    func testPerformPeriodicTickFlushesWhenThresholdExceeded() async throws {
        let (engine, store, counterSource, identitySource, _) = try makeEngine()

        let ssid = try SSID(hex: ssidHex)
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: ssid,
            bssid: bssid1
        )
        identitySource.setObservations([.associated(identity)])
        counterSource.setCounters(interfaceName: "en0", counters: InterfaceCounters(rx: 0, tx: 0, total: 0))

        _ = try await engine.performPeriodicTick()
        let initialCommits = store.getCommittedCount()

        counterSource.setCounters(interfaceName: "en0", counters: InterfaceCounters(rx: 6_000_000, tx: 5_000_000, total: 11_000_000))
        let snapshot = try await engine.performPeriodicTick()
        XCTAssertEqual(snapshot.currentUsageBytes, ByteCount(11_000_000))

        let afterCommits = store.getCommittedCount()
        XCTAssertGreaterThan(afterCommits, initialCommits)
    }

    func testBackwardWallClockDetected() async throws {
        let (engine, store, counterSource, identitySource, clock) = try makeEngine()

        let ssid = try SSID(hex: ssidHex)
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: ssid,
            bssid: bssid1
        )
        identitySource.setObservations([.associated(identity)])
        counterSource.setCounters(interfaceName: "en0", counters: InterfaceCounters(rx: 1_000, tx: 1_000, total: 2_000))

        _ = try await engine.performPeriodicTick()

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.timeZone = timeZone
        let pastDate = Calendar(identifier: .gregorian).date(from: components)!
        clock.setDate(pastDate)

        let snapshot = try await engine.performPeriodicTick()
        XCTAssertEqual(snapshot.globalSafety, GlobalSafetyState.timeAdjustmentRequired)
        XCTAssertEqual(snapshot.timeAdjustmentReason, TimeAdjustmentReasonV1.backwardWallClock)
        _ = store
    }

    func testSleepWakeAndVoluntaryQuit() async throws {
        let (engine, _, counterSource, identitySource, clock) = try makeEngine()

        let ssid = try SSID(hex: ssidHex)
        let identity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: ssid,
            bssid: bssid1
        )
        identitySource.setObservations([.associated(identity)])
        counterSource.setCounters(interfaceName: "en0", counters: InterfaceCounters(rx: 1_000, tx: 1_000, total: 2_000))
        _ = try await engine.performPeriodicTick()

        let sleepSnapshot = try await engine.sleep()
        XCTAssertEqual(sleepSnapshot.connectionState, ConnectionState.disconnected)

        clock.setMonotonic(clock.monotonicNanoseconds() + 1_000_000_000)
        let wakeSnapshot = try await engine.wake()
        XCTAssertEqual(wakeSnapshot.connectionState, ConnectionState.disconnected)

        let quitSnapshot = try await engine.voluntaryQuit()
        XCTAssertEqual(quitSnapshot.connectionState, ConnectionState.disconnected)
    }

    func testSelectProfileAndChangeSettings() async throws {
        let (engine, store, _, _, _) = try makeEngine()

        let snap1 = try await engine.selectProfile(id: profileID)
        XCTAssertEqual(snap1.selectedProfileID, profileID)

        let snap2 = try await engine.changeLimit(profileID: profileID, newLimitBytes: ByteCount(500_000_000))
        XCTAssertEqual(snap2.currentLimitBytes, ByteCount(500_000_000))

        _ = try await engine.changeResetDay(profileID: profileID, newResetDay: 15)
        let resetDay = await engine.state.store.profiles.first?.resetDay
        XCTAssertEqual(resetDay, 15)

        let snap4 = try await engine.manualResetUsage(profileID: profileID)
        XCTAssertEqual(snap4.currentUsageBytes, ByteCount(0))

        let commits = store.getCommittedCount()
        XCTAssertGreaterThan(commits, 0)
    }

   func testSnapshotsAsyncStream() async throws {
       let (engine, _, _, _, _) = try makeEngine()
        let targetProfileID = profileID

       let task = Task<RuntimeSnapshotV1?, Never> {
           for await s in engine.snapshots {
                if s.selectedProfileID == targetProfileID {
                   return s
               }
            }
            return nil
        }

        try await engine.selectProfile(id: profileID)
        let result = await task.value
        XCTAssertEqual(result?.selectedProfileID, profileID)
    }

    private func makeEngine() throws -> (
        engine: RuntimeEngine,
        store: TestEnvelopeStore,
        counterSource: TestCounterSource,
        identitySource: TestWiFiIdentitySource,
        clock: TestClock
    ) {
        let envelope = try makeEnvelope()
        let store = TestEnvelopeStore(initialEnvelope: envelope)
        let counterSource = TestCounterSource()
        let identitySource = TestWiFiIdentitySource()

        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 10
        components.timeZone = timeZone
        let fixedDate = Calendar(identifier: .gregorian).date(from: components)!
        let clock = TestClock(date: fixedDate, monotonic: 1_000_000_000)

        let engine = RuntimeEngine(
            store: store,
            initialEnvelope: envelope,
            counterSource: counterSource,
            identitySource: identitySource,
            clock: clock,
            candidateLifecycle: .production,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )

        return (engine, store, counterSource, identitySource, clock)
    }

    private func makeEnvelope() throws -> StoreEnvelopeV1 {
        let profile = try makeProfile()
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

    private func makeProfile() throws -> ProfileRecord {
        try ProfileRecord(
            profileID: profileID,
            aliasNFC: "Test Profile",
            ssidHex: ssidHex,
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

final class TestClock: ClockProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    private var monotonic: UInt64

    init(date: Date, monotonic: UInt64) {
        self.date = date
        self.monotonic = monotonic
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func monotonicNanoseconds() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return monotonic
    }

    func setDate(_ newDate: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.date = newDate
    }

    func setMonotonic(_ val: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        self.monotonic = val
    }
}

final class TestCounterSource: InterfaceCounterSource, @unchecked Sendable {
    private let lock = NSLock()
    private var counters: [String: InterfaceCounters] = [:]

    func setCounters(interfaceName: String, counters: InterfaceCounters) {
        lock.lock()
        defer { lock.unlock() }
        self.counters[interfaceName] = counters
    }

    func read(interfaceName: String) throws -> InterfaceCounters {
        lock.lock()
        defer { lock.unlock() }
        return counters[interfaceName] ?? InterfaceCounters(rx: 0, tx: 0, total: 0)
    }
}

final class TestWiFiIdentitySource: WiFiIdentitySource, @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [WiFiIdentityObservation] = []

    func setObservations(_ obs: [WiFiIdentityObservation]) {
        lock.lock()
        defer { lock.unlock() }
        self.observations = obs
    }

    func read(interfaceName: String) throws -> WiFiIdentityObservation {
        lock.lock()
        defer { lock.unlock() }
        return observations.first ?? .notAssociated(interfaceName: interfaceName, interfaceIndex: 1)
    }

    func readAll() throws -> [WiFiIdentityObservation] {
        lock.lock()
        defer { lock.unlock() }
        return observations
    }
}

final class TestEnvelopeStore: EnvelopeStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var committed: [(StoreEnvelopeV1, JournalOperation)] = []
    private var current: StoreEnvelopeV1

    init(initialEnvelope: StoreEnvelopeV1) {
        self.current = initialEnvelope
    }

    func commitEnvelope(_ document: StoreEnvelopeV1, operation: JournalOperation) throws {
        lock.lock()
        defer { lock.unlock() }
        committed.append((document, operation))
        current = document
    }

    func loadEnvelope() throws -> StoreLoadResult<StoreEnvelopeV1> {
        lock.lock()
        defer { lock.unlock() }
        return .loaded(current)
    }

    func getCommittedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return committed.count
    }
}
