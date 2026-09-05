import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case systemDefault
    case korean
    case english

    public var displayName: String {
        switch self {
        case .systemDefault: return "System Default"
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

public struct Localization: Sendable {
    public let language: AppLanguage

    public init(language: AppLanguage = .systemDefault) {
        self.language = language
    }

    public var effectiveLanguage: AppLanguage {
        switch language {
        case .korean:
            return .korean
        case .english:
            return .english
        case .systemDefault:
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("ko") {
                return .korean
            }
            return .english
        }
    }

    private var isKorean: Bool {
        effectiveLanguage == .korean
    }

    public static let disconnectedDash: String = "—"

    public static func formatMenuBar(usageBytes: ByteCount?, hasResolvedConnection: Bool) -> String {
        guard hasResolvedConnection, let usageBytes else {
            return disconnectedDash
        }
        return UsageFormatter.formatGB(usageBytes)
    }

    public var muteFor10Minutes: String {
        isKorean ? "10분 동안 알림 끄기" : "Mute for 10 Minutes"
    }

    public var muteFor1Hour: String {
        isKorean ? "1시간 동안 알림 끄기" : "Mute for 1 Hour"
    }

    public var muteForThisCycle: String {
        isKorean ? "이번 주기 동안 알림 끄기" : "Mute for This Cycle"
    }

    public var manualResetTitle: String {
        isKorean ? "사용량 초기화" : "Reset Usage"
    }

    public var manualResetMessage: String {
        isKorean
            ? "현재 사용량을 0으로 초기화하시겠습니까? 통신사에 기록된 실제 데이터 사용량은 초기화되지 않습니다."
            : "Reset the current measured usage to zero? This does not reset the actual data usage recorded by your carrier."
    }

    public var cancel: String {
        isKorean ? "취소" : "Cancel"
    }

    public var resetAction: String {
        isKorean ? "초기화" : "Reset"
    }

    public var disclaimerHotspotScope: String {
        isKorean
            ? "Hotspot Byte Fence는 이 Mac이 지정된 핫스팟을 통해 사용한 데이터만 측정합니다. 핫스팟 기기 자체 또는 다른 기기에서 사용한 셀룰러 데이터는 포함되지 않습니다."
            : "Hotspot Byte Fence measures only data used by this Mac through the selected profile's hotspot. Cellular data used directly by the hotspot device or by other devices is not included."
    }

    public var disclaimerInterfaceMeter: String {
        isKorean
            ? "이 수치는 이 Mac의 Wi‑Fi 인터페이스 기준이며 통신사 청구량과 다를 수 있습니다. 앱 종료·절전 중 사용량은 복구되지 않고, 샘플링 지연으로 설정 한도를 넘을 수 있습니다."
            : "This value is based on this Mac's Wi-Fi interface and may differ from the carrier's billing meter. Usage during application downtime or sleep is not recovered, and sampling delay may allow usage to exceed the configured limit before detection."
    }

    public var disclaimerVPN: String {
        isKorean
            ? "VPN을 사용하는 경우에도 대상 Wi‑Fi를 통해 실제 전송된 암호화 트래픽은 한 번 포함되며, VPN 가상 인터페이스의 사용량을 별도로 더하지 않습니다."
            : "When a VPN uses the target Wi-Fi connection, the encrypted traffic transported over that physical Wi-Fi interface is included once. The VPN tunnel interface is not counted separately."
    }

    public func limitReachedNotificationTitle(profileName: String) -> String {
        isKorean
            ? "[\(profileName)] 데이터 한도 도달"
            : "[\(profileName)] Data Limit Reached"
    }

    public func limitReachedNotificationBody(profileName: String, limitGB: String) -> String {
        isKorean
            ? "목표 사용량(\(limitGB))에 도달하여 핫스팟 연결을 차단하였습니다."
            : "The configured data limit (\(limitGB)) has been reached. Hotspot connection has been disconnected."
    }

    public func warningThresholdNotificationTitle(profileName: String) -> String {
        isKorean
            ? "[\(profileName)] 데이터 한도 90% 도달"
            : "[\(profileName)] 90% of Data Limit Reached"
    }

    public func warningThresholdNotificationBody(profileName: String, limitGB: String) -> String {
        isKorean
            ? "목표 사용량의 90%에 도달했습니다. 곧 핫스팟 연결이 차단될 수 있습니다."
            : "You have used 90% of your \(limitGB) data limit. The hotspot connection may be blocked soon."
    }

    public func blockingFailedNotificationTitle(profileName: String) -> String {
        isKorean
            ? "[\(profileName)] 차단 실패 경고"
            : "[\(profileName)] Blocking Failure Warning"
    }

    public func blockingFailedNotificationBody(profileName: String, reason: String) -> String {
        isKorean
            ? "핫스팟 데이터 차단에 실패했습니다: \(reason)"
            : "Failed to enforce hotspot data block: \(reason)"
    }

    public var usageStateNormal: String {
        isKorean ? "정상" : "Normal"
    }

    public var usageStateNotice: String {
        isKorean ? "주의 (50% 이상)" : "Notice (50%+)"
    }

    public var usageStateWarning: String {
        isKorean ? "경고 (80% 이상)" : "Warning (80%+)"
    }

    public var usageStateCritical: String {
        isKorean ? "위험 (90% 이상)" : "Critical (90%+)"
    }

    public var usageStateLimitReached: String {
        isKorean ? "한도 도달 (100%)" : "Limit Reached (100%)"
    }

    public var menuPauseBlocking: String {
        isKorean ? "차단 일시정지" : "Pause Blocking"
    }

    public var menuResumeBlocking: String {
        isKorean ? "차단 재개" : "Resume Blocking"
    }

    public var menuResetUsage: String {
        isKorean ? "사용량 초기화..." : "Reset Usage..."
    }

    public var menuSettings: String {
        isKorean ? "환경설정..." : "Settings..."
    }

    public var menuQuit: String {
        isKorean ? "Hotspot Byte Fence 종료" : "Quit Hotspot Byte Fence"
    }

    public var languageMenuTitle: String {
        isKorean ? "언어 설정" : "Language"
    }

    public var languageSystemDefault: String {
        isKorean ? "시스템 기본" : "System Default"
    }

    public var launchAtLoginMenuTitle: String {
        isKorean ? "Mac 시작 시 자동 실행" : "Launch at Login"
    }

    public var profileAndLimitTabTitle: String {
        isKorean ? "프로필 및 한도" : "Profile & Limit"
    }

    public var noticesTabTitle: String {
        isKorean ? "안내사항" : "Notices"
    }

    public var settingsWindowTitle: String {
        isKorean ? "Hotspot Byte Fence 환경설정" : "Hotspot Byte Fence Settings"
    }

    public var statusMonitoring: String {
        isKorean ? "모니터링 중" : "Monitoring"
    }

    public var statusNeedsBSSIDConfirmation: String {
        isKorean ? "BSSID 승인 필요" : "BSSID Approval Required"
    }

    public var statusUnknownNetwork: String {
        isKorean ? "미등록 핫스팟" : "Unregistered Hotspot"
    }

    public var statusDetected: String {
        isKorean ? "감지됨" : "Detected"
    }

    public var statusNotConnected: String {
        isKorean ? "연결 안 됨" : "Disconnected"
    }

    public var statusWaitingForWiFi: String {
        isKorean ? "Wi-Fi 대기 중" : "Waiting for Wi-Fi"
    }

    public var menuUsagePrefix: String {
        isKorean ? "사용량:" : "Usage:"
    }

    public var menuLimitNotSet: String {
        isKorean ? "설정 안 됨" : "Not Set"
    }

    public func formatResetDay(day: UInt) -> String {
        isKorean ? "매월 갱신일: 매월 \(day)일" : "Reset Day: Day \(day) of each month"
    }

    public func formatPresetResetDay(day: UInt) -> String {
        if day == 31 {
            return isKorean ? "매월 말일 (31일)" : "End of month (Day 31)"
        }
        return isKorean ? "매월 \(day)일" : "Day \(day)"
    }

    public var menuSetLimitTitle: String {
        isKorean ? "목표 사용량(한도) 설정" : "Set Target Limit"
    }

    public var menuCustomInput: String {
        isKorean ? "직접 입력..." : "Custom..."
    }

    public var menuSetResetDayTitle: String {
        isKorean ? "매월 갱신일 설정" : "Set Monthly Reset Day"
    }

    public var menuCustomResetDayInput: String {
        isKorean ? "직접 입력 (1~31일)..." : "Custom (Days 1~31)..."
    }

    public func formatRegisterHotspot(ssid: String) -> String {
        isKorean ? "'\(ssid)'를 핫스팟으로 등록..." : "Register '\(ssid)' as Hotspot..."
    }

    public var promptCustomLimitTitle: String {
        isKorean ? "목표 사용량(한도) 설정" : "Set Target Limit"
    }

    public var promptCustomLimitMessage: String {
        isKorean ? "원하는 데이터 한도(GB 단위)를 입력하세요:" : "Enter the desired data limit (in GB):"
    }

    public var promptCustomLimitPlaceholder: String {
        isKorean ? "예: 12.5" : "e.g. 12.5"
    }

    public var confirm: String {
        isKorean ? "확인" : "OK"
    }

    public var promptCustomResetDayTitle: String {
        isKorean ? "매월 갱신일 설정" : "Set Monthly Reset Day"
    }

    public var promptCustomResetDayMessage: String {
        isKorean ? "매월 데이터 사용량이 초기화되는 일자(1~31)를 입력하세요:" : "Enter the monthly reset day (1~31):"
    }

    public var defaultHotspotAlias: String {
        isKorean ? "내 핫스팟" : "My Hotspot"
    }

    public var profileSettingsGroupTitle: String {
        isKorean ? "핫스팟 프로필 설정" : "Hotspot Profile Settings"
    }

    public var profileAliasLabel: String {
        isKorean ? "프로필 별칭:" : "Profile Alias:"
    }

    public var profileAliasPlaceholder: String {
        isKorean ? "예: 내 아이폰 핫스팟" : "e.g. My iPhone Hotspot"
    }

    public var profileLimitLabel: String {
        isKorean ? "목표 한도 (GB):" : "Target Limit (GB):"
    }

    public var profileResetDayLabel: String {
        isKorean ? "매월 갱신일:" : "Monthly Reset Day:"
    }

    public var detectedWiFiLabel: String {
        isKorean ? "감지된 Wi-Fi:" : "Detected Wi-Fi:"
    }

    public var saveSettingsButtonTitle: String {
        isKorean ? "등록" : "Register"
    }

    public var savedSuccessMessage: String {
        isKorean ? "저장되었습니다." : "Settings saved."
    }

    public var savedLimitAndResetDayMessage: String {
        isKorean ? "한도 및 갱신일이 변경되었습니다." : "Limit and reset day updated."
    }

    public var savedNoWiFiMessage: String {
        isKorean ? "현재 연결된 Wi-Fi가 없습니다." : "No Wi-Fi currently connected."
    }

    public var noticesHeaderTitle: String {
        isKorean ? "측정 기준 및 고지사항" : "Measurement Standards & Disclaimers"
    }

    public var noticeHotspotScopeTitle: String {
        isKorean ? "• 핫스팟 데이터 측정 범위" : "• Hotspot Data Measurement Scope"
    }

    public var noticeInterfaceMeterTitle: String {
        isKorean ? "• 통신사 과금과의 차이" : "• Differences with Carrier Billing"
    }

    public var noticeVPNTitle: String {
        isKorean ? "• VPN 사용 시 동작" : "• Behavior When Using VPN"
    }

    public var unlimitedLabel: String {
        isKorean ? "무제한" : "Unlimited"
    }

    public var unlimitedShortLabel: String {
        isKorean ? "무제한" : "∞"
    }

    public var statusLocationPermissionRequired: String {
        isKorean ? "위치 권한 필요" : "Location Permission Required"
    }

    public var locationPermissionRequiredMessage: String {
        isKorean ? "Wi-Fi 네트워크 이름을 확인하려면 위치 권한이 필요합니다. (시스템 설정 > 개인정보 보호 및 보안 > 위치 서비스)" : "Location permission is required to read Wi-Fi network identity. (System Settings > Privacy & Security > Location Services)"
    }

    public var openLocationSettingsTitle: String {
        isKorean ? "위치 권한 허용 및 설정 열기..." : "Grant Location Permission..."
    }

    public var grantButtonTitle: String {
        isKorean ? "권한 허용" : "Grant"
    }
}
