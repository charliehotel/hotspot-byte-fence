import SwiftUI
import HotspotByteFenceCore

struct PreferencesView: View {
    let localization: Localization
    let language: (StoreLanguageOverrideV1) -> Void
    let toggleLaunch: () -> Void
    let launchEnabled: Bool
    let locationGranted: Bool
    let openLocation: () -> Void

    private var isKorean: Bool { localization.effectiveLanguage == .korean }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localization.effectiveLanguage == .korean ? "일반" : "General")
                .font(.system(size: 18, weight: .semibold))
            settingsCard {
                VStack(spacing: 0) {
                    preferenceRow(title: localization.languageMenuTitle, systemImage: "globe") {
                        LanguagePreferencePicker(localization: localization, onChange: language)
                            .frame(width: 150, height: 24)
                    }
                    Divider().padding(.leading, 36)
                    preferenceRow(title: localization.launchAtLoginMenuTitle, systemImage: "play.desktopcomputer") {
                        Toggle("", isOn: Binding(get: { launchEnabled }, set: { _ in toggleLaunch() }))
                            .labelsHidden().toggleStyle(.switch)
                            .accessibilityLabel(localization.launchAtLoginMenuTitle)
                    }
                }
            }

            Text(isKorean ? "알림" : "Notifications")
                .font(.system(size: 18, weight: .semibold))
            settingsCard {
                VStack(spacing: 0) {
                    ForEach(NotificationPreference.allCases, id: \.self) { preference in
                        if preference != .automaticProfileChange { Divider().padding(.leading, 30) }
                        preferenceRow(title: localization.notificationPreferenceTitle(preference), systemImage: "bell") {
                            NotificationPreferenceToggle(preference: preference, localization: localization)
                        }
                    }
                }
            }

            Text(isKorean ? "권한" : "Permissions")
                .font(.system(size: 18, weight: .semibold))
            settingsCard {
                preferenceRow(title: isKorean ? "Wi-Fi 위치 권한" : "Wi-Fi Location Permission", systemImage: "location.fill") {
                    HStack(spacing: 10) {
                        Circle().fill(locationGranted ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(locationGranted ? (isKorean ? "허용됨" : "Allowed") : (isKorean ? "허용 필요" : "Action needed"))
                            .foregroundStyle(locationGranted ? .green : .secondary)
                        if !locationGranted { Button(isKorean ? "설정 열기" : "Open Settings", action: openLocation).controlSize(.small) }
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
    }

    private func preferenceRow<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).frame(width: 20).foregroundStyle(.secondary)
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            content().fixedSize()
        }
        .padding(.vertical, 8)
    }
}

private struct LanguagePreferencePicker: NSViewRepresentable {
    let localization: Localization
    let onChange: (StoreLanguageOverrideV1) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectLanguage(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onChange = onChange
        button.removeAllItems()
        button.addItems(withTitles: [localization.languageSystemDefault, "한국어", "English"])
        button.selectItem(at: localization.language == .korean ? 1 : localization.language == .english ? 2 : 0)
        button.setAccessibilityLabel(localization.languageMenuTitle)
    }

    @MainActor final class Coordinator: NSObject {
        var onChange: (StoreLanguageOverrideV1) -> Void
        init(onChange: @escaping (StoreLanguageOverrideV1) -> Void) { self.onChange = onChange }
        @objc func selectLanguage(_ sender: NSPopUpButton) {
            onChange(sender.indexOfSelectedItem == 1 ? .ko : sender.indexOfSelectedItem == 2 ? .en : .system)
        }
    }
}

private struct NotificationPreferenceToggle: View {
    let preference: NotificationPreference
    let localization: Localization
    @AppStorage private var enabled: Bool

    init(preference: NotificationPreference, localization: Localization) {
        self.preference = preference
        self.localization = localization
        _enabled = AppStorage(wrappedValue: true, preference.key)
    }

    var body: some View {
        Toggle(localization.notificationPreferenceTitle(preference), isOn: $enabled)
            .labelsHidden().toggleStyle(.switch)
    }
}
