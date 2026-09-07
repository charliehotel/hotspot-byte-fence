import Foundation
#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
#if canImport(CoreLocation)
import CoreLocation
#endif

@MainActor
public final class SettingsState: ObservableObject {
    let engine: RuntimeEngine
    @Published public var localization: Localization
    @Published public var alias: String
    @Published public var limitGBText: String = "10.0"
    @Published public var sliderPosition: Double = 2.0
    @Published public var isUnlimited: Bool = false
    @Published public var resetDay: Int = 1
    @Published public var currentSSID: String?
    @Published public var currentBSSID: String?
    @Published public var currentInterface: String?
    @Published public var savedMessage: String?
    private var isUpdatingFromSlider: Bool = false
    private var isRegisteringProfile: Bool
    private var editingProfileID: UUID?

    public init(
        engine: RuntimeEngine,
        localization: Localization = Localization(),
        registeringProfile: Bool = false,
        editingProfileID: UUID? = nil
    ) {
        self.engine = engine
        self.localization = localization
        self.isRegisteringProfile = registeringProfile
        self.editingProfileID = editingProfileID
        self.alias = localization.defaultHotspotAlias
        self.sliderPosition = gbToSliderPosition(10.0)
        refreshFromEngine()
    }

    public func refreshFromEngine() {
        Task { [weak self] in
            guard let self else { return }
            let store = await self.engine.currentStore()
            let appLang: AppLanguage
            switch store.languageOverride {
            case .ko: appLang = .korean
            case .en: appLang = .english
            default: appLang = .systemDefault
            }
            let newLoc = Localization(language: appLang)
            self.localization = newLoc
            if self.alias == "내 핫스팟" || self.alias == "My Hotspot" || self.alias.isEmpty {
                self.alias = newLoc.defaultHotspotAlias
            }

            let resolvedIdentity = await self.engine.currentResolvedIdentity()
            if let identity = resolvedIdentity {
                let name = String(bytes: identity.ssid.bytes, encoding: .utf8) ?? identity.ssid.hex
                self.currentSSID = name
                self.currentBSSID = identity.bssid.description
                self.currentInterface = identity.interfaceName
                if self.alias.isEmpty || self.alias == "내 핫스팟" || self.alias == "My Hotspot" {
                    self.alias = name
                }
            }
            let snapshot = await self.engine.currentSnapshot()
            if self.isRegisteringProfile {
                if let identity = resolvedIdentity,
                   let profile = store.profiles.first(where: {
                       $0.interfaceName == identity.interfaceName && $0.ssidHex == identity.ssid.hex
                   }) {
                    let gb = Double(profile.limitBytes.rawValue) / 1_000_000_000.0
                    self.limitGBText = String(format: "%.1f", gb)
                    self.sliderPosition = self.gbToSliderPosition(gb)
                    self.resetDay = Int(profile.resetDay)
                    self.alias = profile.aliasNFC
                }
            } else {
                if let profileID = self.editingProfileID,
                   let profile = store.profiles.first(where: { $0.profileID == profileID }) {
                    if profile.limitBytes.rawValue >= ProfileRecord.maximumLimitBytes {
                        self.isUnlimited = true
                        self.limitGBText = newLoc.unlimitedLabel
                        self.sliderPosition = 7.0
                    } else {
                        let gb = Double(profile.limitBytes.rawValue) / 1_000_000_000.0
                        self.isUnlimited = false
                        self.limitGBText = String(format: "%.1f", gb)
                        self.sliderPosition = self.gbToSliderPosition(gb)
                    }
                    self.resetDay = Int(profile.resetDay)
                    self.alias = profile.aliasNFC
                } else if let limit = snapshot.currentLimitBytes {
                    let gb = Double(limit.rawValue) / 1_000_000_000.0
                    self.limitGBText = String(format: "%.1f", gb)
                    self.sliderPosition = self.gbToSliderPosition(gb)
                }
                if self.editingProfileID == nil,
                   let profileID = snapshot.selectedProfileID,
                   let profile = store.profiles.first(where: { $0.profileID == profileID }) {
                    self.resetDay = Int(profile.resetDay)
                    self.alias = profile.aliasNFC
                }
            }
        }
    }

    public func prepareForProfileRegistration() {
        isRegisteringProfile = true
        editingProfileID = nil
        alias = localization.defaultHotspotAlias
        limitGBText = "10.0"
        sliderPosition = gbToSliderPosition(10.0)
        isUnlimited = false
        resetDay = 1
        savedMessage = nil
        refreshFromEngine()
    }

    public func prepareForProfileEditing() {
        isRegisteringProfile = false
        editingProfileID = nil
        refreshFromEngine()
    }

    public func prepareForProfileEditing(profileID: UUID) {
        isRegisteringProfile = false
        editingProfileID = profileID
        refreshFromEngine()
    }

    public func saveProfile() {
        let limitBytes: ByteCount
        let trimmed = limitGBText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isUnlimited || trimmed == "무제한" || trimmed.lowercased() == "unlimited" {
            limitBytes = ByteCount(ProfileRecord.maximumLimitBytes)
        } else if let gb = Double(trimmed) {
            if gb <= 0 {
                limitBytes = ByteCount(ProfileRecord.minimumLimitBytes)
            } else {
                let calculated = UInt64(gb * 1_000_000_000.0)
                let clamped = max(ProfileRecord.minimumLimitBytes, min(ProfileRecord.maximumLimitBytes, calculated))
                limitBytes = ByteCount(clamped)
            }
        } else {
            return
        }
        let day = UInt(max(1, min(31, resetDay)))
        Task { [weak self] in
            guard let self else { return }
            let store = await self.engine.currentStore()
            let snapshot = await self.engine.currentSnapshot()
            let selectedID = self.isRegisteringProfile ? nil : (self.editingProfileID ?? snapshot.selectedProfileID)
            let targetProfile = selectedID.flatMap { id in store.profiles.first(where: { $0.profileID == id }) }

            if let targetProfile {
                _ = try? await self.engine.editProfile(
                    profileID: targetProfile.profileID,
                    alias: self.alias.isEmpty ? self.localization.defaultHotspotAlias : self.alias,
                    limitBytes: limitBytes,
                    resetDay: day
                )
                _ = try? await self.engine.performPeriodicTick()
                self.savedMessage = self.localization.savedSuccessMessage
                await MainActor.run {
                    SettingsWindowController.shared.close()
                }
            } else if let identity = await self.engine.currentResolvedIdentity() {
                _ = try? await self.engine.createOrUpdateProfile(
                    alias: self.alias.isEmpty ? self.localization.defaultHotspotAlias : self.alias,
                    limitBytes: limitBytes,
                    resetDay: day,
                    interfaceName: identity.interfaceName,
                    ssidHex: identity.ssid.hex,
                    bssid: identity.bssid
                )
                _ = try? await self.engine.performPeriodicTick()
                self.savedMessage = self.localization.savedSuccessMessage
                await MainActor.run {
                    SettingsWindowController.shared.close()
                }
            } else {
                self.savedMessage = self.localization.locationPermissionRequiredMessage
            }
        }
    }

    public func requestLocationPermission() {
        #if canImport(CoreLocation)
        let manager = CLLocationManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        #endif
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    public func updateSliderFromText() {
        guard !isUpdatingFromSlider else { return }
        let trimmed = limitGBText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "무제한" || trimmed.lowercased() == "unlimited" {
            isUnlimited = true
            sliderPosition = 7.0
            return
        }
        guard let gb = Double(trimmed), gb >= 0 else { return }
        isUnlimited = false
        sliderPosition = gbToSliderPosition(gb)
    }

    public func gbToSliderPosition(_ gb: Double) -> Double {
        if gb <= 0 { return 0.0 }
        if gb <= 5 { return (gb / 5.0) * 1.0 }
        if gb <= 10 { return 1.0 + ((gb - 5.0) / 5.0) * 1.0 }
        if gb <= 20 { return 2.0 + ((gb - 10.0) / 10.0) * 1.0 }
        if gb <= 30 { return 3.0 + ((gb - 20.0) / 10.0) * 1.0 }
        if gb <= 50 { return 4.0 + ((gb - 30.0) / 20.0) * 1.0 }
        if gb <= 100 { return 5.0 + ((gb - 50.0) / 50.0) * 1.0 }
        return 7.0
    }

    public func onSliderChanged(_ pos: Double) {
        isUpdatingFromSlider = true
        defer { isUpdatingFromSlider = false }

        if pos >= 6.85 {
            isUnlimited = true
            limitGBText = localization.unlimitedLabel
            return
        }
        isUnlimited = false

        let landmarks: [(Double, Double)] = [
            (1.0, 5.0),
            (2.0, 10.0),
            (3.0, 20.0),
            (4.0, 30.0),
            (5.0, 50.0),
            (6.0, 100.0)
        ]
        for (landmarkPos, landmarkGB) in landmarks {
            if abs(pos - landmarkPos) < 0.08 {
                let formatted = String(format: "%.1f", landmarkGB)
                if limitGBText != formatted {
                    limitGBText = formatted
                }
                return
            }
        }

        let gb: Double
        if pos <= 0.0 {
            gb = 0.0
        } else if pos <= 1.0 {
            gb = (pos * 50.0).rounded() / 10.0
        } else if pos <= 2.0 {
            gb = (5.0 + (pos - 1.0) * 5.0).rounded()
        } else if pos <= 3.0 {
            gb = (10.0 + (pos - 2.0) * 10.0).rounded()
        } else if pos <= 4.0 {
            gb = (20.0 + (pos - 3.0) * 10.0).rounded()
        } else if pos <= 5.0 {
            gb = (30.0 + (pos - 4.0) * 20.0).rounded()
        } else if pos <= 6.0 {
            gb = (50.0 + (pos - 5.0) * 50.0).rounded()
        } else {
            gb = 100.0
        }
        let formatted = String(format: "%.1f", gb)
        if limitGBText != formatted {
            limitGBText = formatted
        }
    }
}

struct SliderRulerView: View {
    let unlimitedLabel: String
    private let labels = ["0", "5", "10", "20", "30", "50", "100"]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let thumbInset: CGFloat = 8
            let usableWidth = max(0, w - thumbInset * 2)
            ZStack(alignment: .top) {
                ForEach(0..<8) { i in
                    let fraction = CGFloat(i) / 7.0
                    let x = thumbInset + usableWidth * fraction
                    let labelText = i < 7 ? labels[i] : unlimitedLabel
                    VStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 1, height: 3)
                        Text(labelText)
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                    .position(x: x, y: 7)
                }
            }
        }
        .frame(height: 14)
    }
}

public struct SettingsView: View {
    @ObservedObject var state: SettingsState

    public init(state: SettingsState) {
        self.state = state
    }

    public var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox(label: Text(state.localization.profileSettingsGroupTitle).bold()) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(state.localization.profileAliasLabel)
                                .frame(width: 110, alignment: .trailing)
                            TextField(state.localization.profileAliasPlaceholder, text: $state.alias)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text(state.localization.profileLimitLabel)
                                .frame(width: 110, alignment: .trailing)
                            TextField("10.0", text: $state.limitGBText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: state.limitGBText) { _ in
                                    state.updateSliderFromText()
                                }
                            Text("GB")
                                .frame(width: 24, alignment: .leading)
                            VStack(spacing: 1) {
                                Slider(value: Binding(
                                    get: { state.sliderPosition },
                                    set: { newPos in
                                        state.sliderPosition = newPos
                                        state.onSliderChanged(newPos)
                                    }
                                ), in: 0.0...7.0)
                                SliderRulerView(unlimitedLabel: state.localization.unlimitedShortLabel)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        HStack {
                            Text(state.localization.profileResetDayLabel)
                                .frame(width: 110, alignment: .trailing)
                            Picker("", selection: $state.resetDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text(state.localization.formatPresetResetDay(day: UInt(day))).tag(day)
                                }
                            }
                            .frame(width: 140)
                        }

                        if let ssid = state.currentSSID {
                            HStack {
                                Text(state.localization.detectedWiFiLabel)
                                    .frame(width: 110, alignment: .trailing)
                                Text(ssid).bold()
                                if let ifName = state.currentInterface {
                                    Text("(\(ifName))").foregroundColor(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                Text(state.localization.detectedWiFiLabel)
                                    .frame(width: 110, alignment: .trailing)
                                Text(state.localization.statusLocationPermissionRequired)
                                    .foregroundColor(.secondary)
                                Button(state.localization.grantButtonTitle) {
                                    state.requestLocationPermission()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(6)
                }

                HStack {
                    if let msg = state.savedMessage {
                        Text(msg)
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                    Spacer()
                    Button(state.localization.saveSettingsButtonTitle) {
                        state.saveProfile()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
        }
        .frame(width: 480, height: 260)
    }
}

@MainActor
public final class SettingsWindowController {
    public static let shared = SettingsWindowController()
    public private(set) var window: NSWindow?
    private var state: SettingsState?

    public func show(
        engine: RuntimeEngine,
        localization: Localization = Localization(),
        registeringProfile: Bool = false,
        profileID: UUID? = nil
    ) {
        if let window {
            updateLocalization(localization)
            if registeringProfile {
                state?.prepareForProfileRegistration()
            } else {
                if let profileID { state?.prepareForProfileEditing(profileID: profileID) } else { state?.prepareForProfileEditing() }
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let state = SettingsState(
            engine: engine,
            localization: localization,
            registeringProfile: registeringProfile,
            editingProfileID: registeringProfile ? nil : profileID
        )
        self.state = state
        let hostingController = NSHostingController(rootView: SettingsView(state: state))
        let win = NSWindow(contentViewController: hostingController)
        win.title = localization.settingsWindowTitle
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.center()
        win.isReleasedWhenClosed = false
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        self.window?.close()
    }

    public func updateLocalization(_ localization: Localization) {
        if let state = self.state {
            if state.alias == "내 핫스팟" || state.alias == "My Hotspot" || state.alias.isEmpty {
                state.alias = localization.defaultHotspotAlias
            }
            state.localization = localization
        }
        self.window?.title = localization.settingsWindowTitle
    }
}
#endif
