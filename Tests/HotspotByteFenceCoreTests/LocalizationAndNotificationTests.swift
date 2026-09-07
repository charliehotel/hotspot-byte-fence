import Foundation
import XCTest
@testable import HotspotByteFenceCore

final class LocalizationAndNotificationTests: XCTestCase {
    func testNotificationPreferencesPersistAndMapEveryCategory() throws {
        let suite = "HBF.NotificationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for preference in NotificationPreference.allCases {
            XCTAssertTrue(preference.isEnabled(in: defaults))
            defaults.set(false, forKey: preference.key)
            XCTAssertFalse(preference.isEnabled(in: try XCTUnwrap(UserDefaults(suiteName: suite))))
            defaults.set(true, forKey: preference.key)
        }
        XCTAssertEqual(NotificationCategory.profileActivated.preference, .automaticProfileChange)
        XCTAssertEqual(NotificationCategory.limitReached.preference, .networkBlocking)
        XCTAssertEqual(NotificationCategory.blockingFailed.preference, .networkBlocking)
        XCTAssertEqual(NotificationCategory.usage50.preference, .usage50)
        XCTAssertEqual(NotificationCategory.usage80.preference, .usage80)
        XCTAssertEqual(NotificationCategory.warningThreshold.preference, .usage90)
    }

    func testUsageNotificationCrossingsAreIndependentAndResetWithCycleOrUsage() {
        var tracker = UsageNotificationTracker()
        let first = UUID(), second = UUID()
        func observe(_ id: UUID, _ percent: Double, _ cycle: String = "2026-09-01",
                     _ protection: ProtectionState = .strongBlockingReady, _ paused: Bool = false) -> [NotificationCategory] {
            tracker.observe(profileID: id, cycle: cycle, percent: percent, protection: protection, paused: paused)
        }
        XCTAssertEqual(observe(first, 49), [])
        XCTAssertEqual(observe(first, 50), [.usage50])
        XCTAssertEqual(observe(first, 51), [])
        XCTAssertEqual(observe(first, 80), [.usage80])
        XCTAssertEqual(observe(first, 90), [.warningThreshold])
        XCTAssertEqual(observe(second, 50), [.usage50])
        XCTAssertEqual(observe(first, 91), [])
        XCTAssertEqual(observe(first, 0), [])
        XCTAssertEqual(observe(first, 50), [.usage50])
        XCTAssertEqual(observe(first, 50, "2026-10-01"), [.usage50])
        XCTAssertEqual(observe(first, 100, "2026-10-01", .blockingPaused, true), [])
        XCTAssertEqual(observe(first, 100, "2026-10-01", .blockingFailed), [.blockingFailed])
        XCTAssertEqual(observe(first, 100, "2026-10-01", .blockingFailed), [])
        XCTAssertEqual(observe(first, 100, "2026-10-01", .limitReached), [.limitReached])
        XCTAssertEqual(observe(first, 100, "2026-10-01", .limitReached), [])
        XCTAssertEqual(tracker.observe(profileID: UUID(), cycle: "2026-10-01", percent: 91,
            protection: .strongBlockingReady, paused: false, enabledThresholds: [.usage80]), [.usage80])
    }

    func testLocalizationLanguageResolution() {
        let korean = Localization(language: .korean)
        XCTAssertEqual(korean.effectiveLanguage, .korean)
        XCTAssertEqual(korean.muteFor10Minutes, "10분 동안 알림 끄기")
        XCTAssertEqual(korean.muteFor1Hour, "1시간 동안 알림 끄기")
        XCTAssertEqual(korean.muteForThisCycle, "이번 주기 동안 알림 끄기")
        XCTAssertEqual(korean.manualResetTitle, "사용량 초기화")
        XCTAssertEqual(korean.cancel, "취소")
        XCTAssertEqual(korean.resetAction, "초기화")
        XCTAssertEqual(korean.menuPauseBlocking, "차단 일시정지")
        XCTAssertEqual(korean.menuResumeBlocking, "차단 재개")
        XCTAssertEqual(korean.menuProfilesTitle, "프로필")
        XCTAssertEqual(korean.menuRegisterProfileTitle, "프로필 등록...")
        XCTAssertEqual(korean.menuNoProfilesRegistered, "(등록된 프로필 없음)")
        XCTAssertEqual(korean.formatEditProfile(alias: "핫스팟"), "'핫스팟' 편집...")
        XCTAssertEqual(korean.menuEditProfileTitle, "프로필 편집...")

        let english = Localization(language: .english)
        XCTAssertEqual(english.effectiveLanguage, .english)
        XCTAssertEqual(english.muteFor10Minutes, "Mute for 10 Minutes")
        XCTAssertEqual(english.muteFor1Hour, "Mute for 1 Hour")
        XCTAssertEqual(english.muteForThisCycle, "Mute for This Cycle")
        XCTAssertEqual(english.manualResetTitle, "Reset Usage")
        XCTAssertEqual(english.cancel, "Cancel")
        XCTAssertEqual(english.resetAction, "Reset")
        XCTAssertEqual(english.menuPauseBlocking, "Pause Blocking")
        XCTAssertEqual(english.menuResumeBlocking, "Resume Blocking")
        XCTAssertEqual(english.menuProfilesTitle, "Profiles")
        XCTAssertEqual(english.menuRegisterProfileTitle, "Register Profile...")
        XCTAssertEqual(english.menuNoProfilesRegistered, "(No Registered Profiles)")
        XCTAssertEqual(english.formatEditProfile(alias: "Hotspot"), "Edit 'Hotspot'...")
        XCTAssertEqual(english.menuEditProfileTitle, "Edit Profile...")
    }

    func testLocalizationNotificationStrings() {
        let korean = Localization(language: .korean)
        XCTAssertEqual(korean.limitReachedNotificationTitle(profileName: "MyHotspot"), "[MyHotspot] 데이터 한도 도달")
        XCTAssertEqual(korean.limitReachedNotificationBody(profileName: "MyHotspot", limitGB: "4.50GB"), "목표 사용량(4.50GB)에 도달하여 핫스팟 연결을 차단하였습니다.")
        XCTAssertEqual(korean.blockingFailedNotificationTitle(profileName: "MyHotspot"), "[MyHotspot] 차단 실패 경고")
        XCTAssertEqual(korean.blockingFailedNotificationBody(profileName: "MyHotspot", reason: "timeout"), "핫스팟 데이터 차단에 실패했습니다: timeout")
        XCTAssertEqual(korean.profileActivatedNotificationTitle(profileName: "MyHotspot"), "[MyHotspot] 프로필 자동 변경")
        XCTAssertEqual(korean.profileActivatedNotificationBody(profileName: "MyHotspot"), "\"MyHotspot\" 프로필로 자동 변경됐습니다.")

        let english = Localization(language: .english)
        XCTAssertEqual(english.limitReachedNotificationTitle(profileName: "MyHotspot"), "[MyHotspot] Data Limit Reached")
        XCTAssertEqual(english.limitReachedNotificationBody(profileName: "MyHotspot", limitGB: "4.50GB"), "The configured data limit (4.50GB) has been reached. Hotspot connection has been disconnected.")
        XCTAssertEqual(english.blockingFailedNotificationTitle(profileName: "MyHotspot"), "[MyHotspot] Blocking Failure Warning")
        XCTAssertEqual(english.blockingFailedNotificationBody(profileName: "MyHotspot", reason: "timeout"), "Failed to enforce hotspot data block: timeout")
        XCTAssertEqual(english.profileActivatedNotificationTitle(profileName: "MyHotspot"), "[MyHotspot] Profile Automatically Changed")
        XCTAssertEqual(english.profileActivatedNotificationBody(profileName: "MyHotspot"), "Automatically changed to the \"MyHotspot\" profile.")
    }

    func testAutomaticProfileActivationDetectorWaitsForProfileSnapshotAfterNetworkChange() throws {
        let oldProfileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let newProfileID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let oldIdentity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: "6f6c64"),
            bssid: try BSSID(string: "00:11:22:33:44:55")
        )
        let newIdentity = WiFiIdentitySnapshot(
            interfaceName: "en0",
            interfaceIndex: 1,
            linkState: .associated,
            ssid: try SSID(hex: "6e6577"),
            bssid: try BSSID(string: "AA:BB:CC:DD:EE:FF")
        )
        let makeSnapshot = { (profileID: UUID?) in
            RuntimeSnapshotV1(
                globalSafety: .normal,
                connectionState: profileID == nil ? .disconnected : .monitoring,
                selectionState: profileID == nil ? .none : .selectedConnected,
                protectionState: .blockingNotGuaranteed,
                candidateLifecycle: .production,
                connectedProfileID: profileID,
                selectedProfileID: profileID,
                storeRevision: DecimalUInt64(rawValue: 1)
            )
        }
        var detector = AutomaticProfileActivationDetector()

        XCTAssertNil(detector.profileIDToNotify(snapshot: makeSnapshot(oldProfileID), identity: oldIdentity))
        XCTAssertNil(detector.profileIDToNotify(snapshot: makeSnapshot(oldProfileID), identity: newIdentity))
        XCTAssertEqual(detector.profileIDToNotify(snapshot: makeSnapshot(newProfileID), identity: newIdentity), newProfileID)
        XCTAssertNil(detector.profileIDToNotify(snapshot: makeSnapshot(newProfileID), identity: newIdentity))
    }

    func testLocalizationMenuBarFormatting() {
        XCTAssertEqual(Localization.formatMenuBar(usageBytes: nil, hasResolvedConnection: false), "—")
        XCTAssertEqual(Localization.formatMenuBar(usageBytes: ByteCount(1_000_000_000), hasResolvedConnection: false), "—")
        XCTAssertEqual(Localization.formatMenuBar(usageBytes: nil, hasResolvedConnection: true), "—")
        XCTAssertEqual(Localization.formatMenuBar(usageBytes: ByteCount(4_500_000_000), hasResolvedConnection: true), "4.50GB")
        XCTAssertEqual(Localization.formatMenuBar(usageBytes: ByteCount(4_505_000_000), hasResolvedConnection: true), "4.51GB")
    }

    func testNotificationEvaluatorLimitReached() throws {
        let record = try ProfileNotificationRecord(
            successNotifiedCycleDate: nil,
            failureMute: .none,
            muteExpiresAt: nil,
            muteCycleDate: nil,
            lastFailureNotificationAt: nil
        )
        let outcome1 = try NotificationEvaluator.evaluateLimitReached(record: record, currentCycleDate: "2026-09-01")
        guard case let .deliver(updated) = outcome1 else {
            XCTFail("Expected delivery for new cycle")
            return
        }
        XCTAssertEqual(updated.successNotifiedCycleDate, "2026-09-01")

        let outcome2 = try NotificationEvaluator.evaluateLimitReached(record: updated, currentCycleDate: "2026-09-01")
        XCTAssertEqual(outcome2, .suppressed(reason: .alreadyNotifiedInCycle))

        let outcome3 = try NotificationEvaluator.evaluateLimitReached(record: updated, currentCycleDate: "2026-10-01")
        guard case let .deliver(updatedNewCycle) = outcome3 else {
            XCTFail("Expected delivery for subsequent cycle")
            return
        }
        XCTAssertEqual(updatedNewCycle.successNotifiedCycleDate, "2026-10-01")
    }

    func testLimitNotificationIsSuppressedWhileBlockingPaused() {
        XCTAssertFalse(NotificationEvaluator.shouldNotifyLimitReached(
            isPauseBlockingActive: true,
            protectionState: .limitReached,
            usagePercent: 100,
            lastNotifiedPercent: 0
        ))
        XCTAssertTrue(NotificationEvaluator.shouldNotifyLimitReached(
            isPauseBlockingActive: false,
            protectionState: .limitReached,
            usagePercent: 100,
            lastNotifiedPercent: 0
        ))
    }

    func testNotificationEvaluatorBlockingFailedMutesAndThrottling() throws {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let record = try ProfileNotificationRecord(
            successNotifiedCycleDate: nil,
            failureMute: .none,
            muteExpiresAt: nil,
            muteCycleDate: nil,
            lastFailureNotificationAt: nil
        )

        let outcome1 = try NotificationEvaluator.evaluateBlockingFailed(record: record, now: baseDate, currentCycleDate: "2026-09-01")
        guard case let .deliver(recAfter1) = outcome1 else {
            XCTFail("Expected delivery initially")
            return
        }
        XCTAssertEqual(recAfter1.lastFailureNotificationAt, baseDate)

        let throttledDate = baseDate.addingTimeInterval(200)
        let outcome2 = try NotificationEvaluator.evaluateBlockingFailed(record: recAfter1, now: throttledDate, currentCycleDate: "2026-09-01")
        XCTAssertEqual(outcome2, .suppressed(reason: .throttledMinInterval))

        let eligibleDate = baseDate.addingTimeInterval(301)
        let outcome3 = try NotificationEvaluator.evaluateBlockingFailed(record: recAfter1, now: eligibleDate, currentCycleDate: "2026-09-01")
        guard case .deliver = outcome3 else {
            XCTFail("Expected delivery after 5m throttle window")
            return
        }

        let muted10m = try NotificationEvaluator.applyMute(record: record, duration: .untilInstant, now: baseDate, currentCycleDate: "2026-09-01")
        XCTAssertEqual(muted10m.failureMute, .untilInstant)
        XCTAssertEqual(muted10m.muteExpiresAt, baseDate.addingTimeInterval(600))
        let mutedOutcome1 = try NotificationEvaluator.evaluateBlockingFailed(record: muted10m, now: baseDate.addingTimeInterval(300), currentCycleDate: "2026-09-01")
        XCTAssertEqual(mutedOutcome1, .suppressed(reason: .mutedUntilInstant))
        let mutedOutcomeExpired = try NotificationEvaluator.evaluateBlockingFailed(record: muted10m, now: baseDate.addingTimeInterval(601), currentCycleDate: "2026-09-01")
        guard case .deliver = mutedOutcomeExpired else {
            XCTFail("Expected delivery after 10m mute expiration")
            return
        }

        let muted1h = try NotificationEvaluator.applyMute1Hour(record: record, now: baseDate)
        XCTAssertEqual(muted1h.muteExpiresAt, baseDate.addingTimeInterval(3600))

        let mutedCycle = try NotificationEvaluator.applyMute(record: record, duration: .untilCycleEnds, now: baseDate, currentCycleDate: "2026-09-01")
        XCTAssertEqual(mutedCycle.failureMute, .untilCycleEnds)
        XCTAssertEqual(mutedCycle.muteCycleDate, "2026-09-01")
        let cycleOutcomeSame = try NotificationEvaluator.evaluateBlockingFailed(record: mutedCycle, now: baseDate.addingTimeInterval(10_000), currentCycleDate: "2026-09-01")
        XCTAssertEqual(cycleOutcomeSame, .suppressed(reason: .mutedUntilCycleEnds))
        let cycleOutcomeNew = try NotificationEvaluator.evaluateBlockingFailed(record: mutedCycle, now: baseDate.addingTimeInterval(10_000), currentCycleDate: "2026-10-01")
        guard case .deliver = cycleOutcomeNew else {
            XCTFail("Expected delivery when cycle changes")
            return
        }
    }

    func testMenuBarViewModelDisconnectedAndConnectedBands() {
        let disconnectedSnapshot = RuntimeSnapshotV1(
            globalSafety: .normal,
            connectionState: .disconnected,
            selectionState: .selectedDisconnected,
            protectionState: .strongBlockingReady,
            candidateLifecycle: .production,
            connectedProfileID: nil,
            selectedProfileID: UUID(),
            selectedProfileAlias: "LTE-Router",
            isPauseBlockingActive: false,
            currentUsageBytes: ByteCount(1_000_000_000),
            currentLimitBytes: ByteCount(5_000_000_000),
            cycleID: nil,
            authorizationAvailable: true,
            storeRevision: DecimalUInt64(rawValue: 1)
        )
        let disconnectedVM = MenuBarViewModel(snapshot: disconnectedSnapshot)
        XCTAssertEqual(disconnectedVM.displayTitle, "—")
        XCTAssertFalse(disconnectedVM.isConnected)
        XCTAssertEqual(disconnectedVM.profileName, "LTE-Router")
        XCTAssertEqual(disconnectedVM.usageState, .normal)
        XCTAssertEqual(disconnectedVM.currentUsageText, "1.00GB")
        XCTAssertEqual(disconnectedVM.limitText, "5GB")
        XCTAssertNil(disconnectedVM.percentageText)
        XCTAssertEqual(disconnectedVM.pauseBlockingToggleTitle, "차단 일시정지")

        let profileID = UUID()
        let makeConnectedSnapshot = { (usage: UInt64, limit: UInt64, isPaused: Bool) -> RuntimeSnapshotV1 in
            RuntimeSnapshotV1(
                globalSafety: .normal,
                connectionState: .monitoring,
                selectionState: .selectedConnected,
                protectionState: isPaused ? .blockingPaused : .strongBlockingReady,
                candidateLifecycle: .production,
                connectedProfileID: profileID,
                selectedProfileID: profileID,
                selectedProfileAlias: "MyPhone",
                isPauseBlockingActive: isPaused,
                currentUsageBytes: ByteCount(usage),
                currentLimitBytes: ByteCount(limit),
                cycleID: nil,
                authorizationAvailable: true,
                storeRevision: DecimalUInt64(rawValue: 1)
            )
        }

        let vmNormal = MenuBarViewModel(snapshot: makeConnectedSnapshot(2_000_000_000, 5_000_000_000, false))
        XCTAssertEqual(vmNormal.displayTitle, "2.00GB")
        XCTAssertTrue(vmNormal.isConnected)
        XCTAssertEqual(vmNormal.usageState, .normal)
        XCTAssertEqual(vmNormal.percentageText, "40.0%")
        XCTAssertEqual(vmNormal.pauseBlockingToggleTitle, "차단 일시정지")

        let vmNotice = MenuBarViewModel(snapshot: makeConnectedSnapshot(2_500_000_000, 5_000_000_000, false))
        XCTAssertEqual(vmNotice.usageState, .notice)
        XCTAssertEqual(vmNotice.percentageText, "50.0%")

        let vmWarning = MenuBarViewModel(snapshot: makeConnectedSnapshot(4_000_000_000, 5_000_000_000, false))
        XCTAssertEqual(vmWarning.usageState, .warning)
        XCTAssertEqual(vmWarning.percentageText, "80.0%")

        let vmCritical = MenuBarViewModel(snapshot: makeConnectedSnapshot(4_500_000_000, 5_000_000_000, false))
        XCTAssertEqual(vmCritical.usageState, .critical)
        XCTAssertEqual(vmCritical.percentageText, "90.0%")

        let vmLimitReached = MenuBarViewModel(snapshot: makeConnectedSnapshot(5_000_000_000, 5_000_000_000, true))
        XCTAssertEqual(vmLimitReached.usageState, .limitReached)
        XCTAssertEqual(vmLimitReached.percentageText, "100.0%")
        XCTAssertEqual(vmLimitReached.pauseBlockingToggleTitle, "차단 재개")
    }

    func testMockLoginItemController() throws {
        let controller = MockLoginItemController(status: .notRegistered)
        XCTAssertEqual(controller.status(), .notRegistered)
        XCTAssertFalse(controller.registerCalled)
        XCTAssertFalse(controller.unregisterCalled)

        try controller.register()
        XCTAssertEqual(controller.status(), .enabled)
        XCTAssertTrue(controller.registerCalled)

        try controller.unregister()
        XCTAssertEqual(controller.status(), .notRegistered)
        XCTAssertTrue(controller.unregisterCalled)
    }

    func testMockNotificationDelivery() async throws {
        let delivery = MockNotificationDelivery()
        XCTAssertTrue(delivery.deliveries.isEmpty)

        try await delivery.deliver(
            title: "[Hotspot] Limit Reached",
            body: "The limit has been reached.",
            category: .limitReached
        )
        XCTAssertEqual(delivery.deliveries.count, 1)
        XCTAssertEqual(delivery.deliveries.first?.title, "[Hotspot] Limit Reached")
        XCTAssertEqual(delivery.deliveries.first?.body, "The limit has been reached.")
        XCTAssertEqual(delivery.deliveries.first?.category, .limitReached)
    }

    func testSettingsTabsAndLocalization() {
        let korean = Localization(language: .korean)
        XCTAssertEqual(korean.languageMenuTitle, "언어 설정")
        XCTAssertEqual(korean.languageSystemDefault, "시스템 기본")
        XCTAssertEqual(korean.launchAtLoginMenuTitle, "Mac 시작 시 자동 실행")
        XCTAssertEqual(korean.profileAndLimitTabTitle, "프로필 및 한도")
        XCTAssertEqual(korean.noticesTabTitle, "안내사항")
        XCTAssertEqual(korean.settingsWindowTitle, "Hotspot Byte Fence 환경설정")
        XCTAssertEqual(korean.profileSettingsGroupTitle, "핫스팟 프로필 설정")
        XCTAssertEqual(korean.profileAliasLabel, "프로필 별칭:")
        XCTAssertEqual(korean.profileLimitLabel, "목표 한도 (GB):")
        XCTAssertEqual(korean.profileResetDayLabel, "매월 갱신일:")
        XCTAssertEqual(korean.noticesHeaderTitle, "측정 기준 및 고지사항")
        XCTAssertEqual(korean.noticeHotspotScopeTitle, "• 핫스팟 데이터 측정 범위")
        XCTAssertEqual(korean.noticeInterfaceMeterTitle, "• 통신사 과금과의 차이")
        XCTAssertEqual(korean.noticeVPNTitle, "• VPN 사용 시 동작")
        XCTAssertEqual(korean.formatPresetResetDay(day: 1), "매월 1일")
        XCTAssertEqual(korean.formatPresetResetDay(day: 31), "매월 말일 (31일)")
        XCTAssertEqual(korean.promptCustomLimitPlaceholder, "예: 12.5")

        let english = Localization(language: .english)
        XCTAssertEqual(english.languageMenuTitle, "Language")
        XCTAssertEqual(english.languageSystemDefault, "System Default")
        XCTAssertEqual(english.launchAtLoginMenuTitle, "Launch at Login")
        XCTAssertEqual(english.profileAndLimitTabTitle, "Profile & Limit")
        XCTAssertEqual(english.noticesTabTitle, "Notices")
        XCTAssertEqual(english.settingsWindowTitle, "Hotspot Byte Fence Settings")
        XCTAssertEqual(english.profileSettingsGroupTitle, "Hotspot Profile Settings")
        XCTAssertEqual(english.profileAliasLabel, "Profile Alias:")
        XCTAssertEqual(english.profileLimitLabel, "Target Limit (GB):")
        XCTAssertEqual(english.profileResetDayLabel, "Monthly Reset Day:")
        XCTAssertEqual(english.noticesHeaderTitle, "Measurement Standards & Disclaimers")
        XCTAssertEqual(english.noticeHotspotScopeTitle, "• Hotspot Data Measurement Scope")
        XCTAssertEqual(english.noticeInterfaceMeterTitle, "• Differences with Carrier Billing")
        XCTAssertEqual(english.noticeVPNTitle, "• Behavior When Using VPN")
        XCTAssertEqual(english.formatPresetResetDay(day: 1), "Day 1")
        XCTAssertEqual(english.formatPresetResetDay(day: 31), "End of month (Day 31)")
        XCTAssertEqual(english.promptCustomLimitPlaceholder, "e.g. 12.5")

        XCTAssertEqual(MenuBarViewModel.formatLimitGB(ByteCount(5_000_000_000)), "5GB")
        XCTAssertEqual(MenuBarViewModel.formatLimitGB(ByteCount(10_000_000_000)), "10GB")
        XCTAssertEqual(MenuBarViewModel.formatLimitGB(ByteCount(500_000_000)), "0.5GB")
        XCTAssertEqual(MenuBarViewModel.formatLimitGB(ByteCount(12_500_000_000)), "12.5GB")
    }
}
