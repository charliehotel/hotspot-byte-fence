import AppKit
import SwiftUI
import HotspotByteFenceCore

struct AppInformationView: View {
    let localization: Localization
    var width: CGFloat = 520
    private var korean: Bool { localization.effectiveLanguage == .korean }

    var body: some View {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text("Hotspot Byte Fence").font(.system(size: 25, weight: .bold))
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? BuildConfiguration.manifest.applicationVersion)")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Text(korean
                         ? "이 Mac의 핫스팟 데이터 사용량을 측정하고, 설정한 한도에 도달하면 Wi-Fi를 꺼서 추가 사용을 제한합니다."
                         : "Monitor this Mac’s hotspot data usage and turn off Wi-Fi at the configured limit to restrict further usage.")
                    Text(korean ? "간단한 사용 방법" : "Getting Started").font(.headline)
                    Text(korean
                         ? "1. 핫스팟이나 Wi-Fi에 연결한 뒤 프로필을 등록합니다.\n2. 프로필의 사용량 한도와 매월 갱신일을 설정합니다.\n3. 메뉴 막대에서 사용량을 확인합니다. 저장된 네트워크에 연결하면 해당 프로필이 자동 적용됩니다.\n4. 잠시 차단을 멈추려면 ‘차단 일시정지’를 사용합니다."
                         : "1. Connect to a hotspot or Wi-Fi and register a profile.\n2. Set its data limit and monthly reset day.\n3. View usage in the menu bar. Connecting to a saved network automatically applies its profile.\n4. Use Pause Blocking to temporarily suspend enforcement.")
                    Divider()
                    Text(localization.noticesHeaderTitle).font(.headline)
                    notice(localization.noticeHotspotScopeTitle, localization.disclaimerHotspotScope)
                    notice(localization.noticeInterfaceMeterTitle, localization.disclaimerInterfaceMeter)
                    notice(localization.noticeVPNTitle, localization.disclaimerVPN)
                }
                .font(.system(size: 13)).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 18)
            }
            .padding(24).textSelection(.enabled)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func notice(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold)
            Text(body)
        }
    }
}
