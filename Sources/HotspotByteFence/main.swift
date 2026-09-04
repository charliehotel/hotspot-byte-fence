import Foundation
import HotspotByteFenceCore

#if canImport(Darwin)
import Darwin
#endif

#if canImport(CoreWLAN)
import CoreWLAN
#endif

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(AppKit)
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var engine: RuntimeEngine?
    private var localization = Localization()
    private let loginController: LoginItemControlling = DarwinLoginItemController()
#if canImport(CoreLocation)
    private var locationManager: CLLocationManager?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
#if canImport(CoreLocation)
        setupLocationManager()
#endif
        startEngine()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = Localization.disconnectedDash
        statusItem?.button?.setAccessibilityIdentifier("MenuBar.UsageValue")
        rebuildMenu(snapshot: nil, identity: nil, store: nil)
    }

    private func rebuildMenu(snapshot: RuntimeSnapshotV1?, identity: WiFiIdentitySnapshot?, store: StoreEnvelopeV1?) {
        let appLang: AppLanguage
        switch store?.languageOverride {
        case .ko: appLang = .korean
        case .en: appLang = .english
        default: appLang = .systemDefault
        }
        self.localization = Localization(language: appLang)

        let menu = NSMenu()
        menu.autoenablesItems = false
        let vm = snapshot.map { MenuBarViewModel(snapshot: $0, localization: localization) }

        let headerItem = NSMenuItem(title: "Hotspot Byte Fence", action: nil, keyEquivalent: "")
        headerItem.isEnabled = true
        headerItem.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil)
        menu.addItem(headerItem)

        let wifiName: String
        let statusText: String
        if let identity {
            let ssidBytes = identity.ssid.bytes
            let name = String(bytes: ssidBytes, encoding: .utf8) ?? identity.ssid.hex
            wifiName = name
            switch snapshot?.connectionState {
            case .monitoring: statusText = localization.statusMonitoring
            case .needsBSSIDConfirmation: statusText = localization.statusNeedsBSSIDConfirmation
            case .unknownNetwork: statusText = localization.statusUnknownNetwork
            case .locationPermissionRequired: statusText = localization.statusLocationPermissionRequired
            default: statusText = localization.statusDetected
            }
        } else {
            wifiName = localization.statusNotConnected
            if snapshot?.connectionState == .locationPermissionRequired {
                statusText = localization.statusLocationPermissionRequired
            } else {
                statusText = localization.statusWaitingForWiFi
            }
        }

        let isRegistered = (snapshot?.connectedProfileID != nil)
        let wifiItem = NSMenuItem(title: "Wi-Fi: \(wifiName) (\(statusText))", action: nil, keyEquivalent: "")
        wifiItem.isEnabled = isRegistered
        wifiItem.image = NSImage(systemSymbolName: identity != nil ? "wifi" : "wifi.slash", accessibilityDescription: nil)
        wifiItem.setAccessibilityIdentifier("Menu.Profile.Connected")
        menu.addItem(wifiItem)

        if snapshot?.connectionState == .locationPermissionRequired {
            let permItem = NSMenuItem(
                title: localization.openLocationSettingsTitle,
                action: #selector(openLocationSettings),
                keyEquivalent: ""
            )
            permItem.target = self
            permItem.image = NSImage(systemSymbolName: "location.circle.fill", accessibilityDescription: nil)
            menu.addItem(permItem)
        }

        let usageTitle = vm?.currentUsageText ?? Localization.disconnectedDash
        let limitTitle = vm?.limitText ?? localization.menuLimitNotSet
        let percentStr = vm?.percentageText.map { " (\($0))" } ?? ""
        let isLimitSet = (snapshot?.currentLimitBytes != nil)
        let usageItem = NSMenuItem(title: "\(localization.menuUsagePrefix) \(usageTitle) / \(limitTitle)\(percentStr)", action: nil, keyEquivalent: "")
        usageItem.isEnabled = isLimitSet
        usageItem.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
        usageItem.setAccessibilityIdentifier("Status.Measurement")
        menu.addItem(usageItem)

        if let profileID = snapshot?.selectedProfileID,
           let profile = store?.profiles.first(where: { $0.profileID == profileID }) {
            let resetItem = NSMenuItem(title: localization.formatResetDay(day: profile.resetDay), action: nil, keyEquivalent: "")
            resetItem.isEnabled = true
            resetItem.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            menu.addItem(resetItem)
        }

        menu.addItem(NSMenuItem.separator())

        let limitMenu = NSMenu()
        let presetLimits: [Double] = [5, 10, 15, 20, 30, 50, 100]
        let isUnlimitedCurrent = (snapshot?.currentLimitBytes?.rawValue ?? 0) >= ProfileRecord.maximumLimitBytes
        for gb in presetLimits {
            let item = NSMenuItem(title: "\(Int(gb)) GB", action: #selector(setPresetLimit(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = gb
            if !isUnlimitedCurrent, let currentLimit = vm?.limitText, currentLimit == "\(Int(gb))GB" {
                item.state = .on
            }
            limitMenu.addItem(item)
        }

        let unlimitedItem = NSMenuItem(
            title: localization.unlimitedLabel,
            action: #selector(setUnlimitedLimit),
            keyEquivalent: ""
        )
        unlimitedItem.target = self
        unlimitedItem.state = isUnlimitedCurrent ? .on : .off
        limitMenu.addItem(unlimitedItem)

        let customLimitItem = NSMenuItem(title: localization.menuCustomInput, action: #selector(promptCustomLimit), keyEquivalent: "")
        customLimitItem.target = self
        customLimitItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        limitMenu.addItem(customLimitItem)

        let setLimitParentItem = NSMenuItem(title: localization.menuSetLimitTitle, action: nil, keyEquivalent: "")
        setLimitParentItem.submenu = limitMenu
        setLimitParentItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        setLimitParentItem.setAccessibilityIdentifier("Command.SetLimit")
        menu.addItem(setLimitParentItem)

        let resetDayMenu = NSMenu()
        let presetDays: [(String, UInt)] = [
            (localization.formatPresetResetDay(day: 1), 1),
            (localization.formatPresetResetDay(day: 11), 11),
            (localization.formatPresetResetDay(day: 21), 21),
            (localization.formatPresetResetDay(day: 25), 25),
            (localization.formatPresetResetDay(day: 31), 31)
        ]
        for (title, day) in presetDays {
            let item = NSMenuItem(title: title, action: #selector(setPresetResetDay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = day
            resetDayMenu.addItem(item)
        }
        let customDayItem = NSMenuItem(title: localization.menuCustomResetDayInput, action: #selector(promptCustomResetDay), keyEquivalent: "")
        customDayItem.target = self
        customDayItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        resetDayMenu.addItem(customDayItem)

        let setResetDayParentItem = NSMenuItem(title: localization.menuSetResetDayTitle, action: nil, keyEquivalent: "")
        setResetDayParentItem.submenu = resetDayMenu
        setResetDayParentItem.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)
        setResetDayParentItem.setAccessibilityIdentifier("Command.SetResetDay")
        menu.addItem(setResetDayParentItem)

        if let identity, snapshot?.connectedProfileID == nil {
            let ssidBytes = identity.ssid.bytes
            let ssidStr = String(bytes: ssidBytes, encoding: .utf8) ?? identity.ssid.hex
            let registerItem = NSMenuItem(
                title: localization.formatRegisterHotspot(ssid: ssidStr),
                action: #selector(registerCurrentWiFiAsHotspot),
                keyEquivalent: ""
            )
            registerItem.target = self
            registerItem.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil)
            registerItem.setAccessibilityIdentifier("Command.RegisterHotspot")
            menu.addItem(registerItem)
        }

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(
            title: vm?.pauseBlockingToggleTitle ?? localization.menuPauseBlocking,
            action: #selector(togglePauseBlocking),
            keyEquivalent: ""
        )
        pauseItem.target = self
        let isPaused = snapshot?.isPauseBlockingActive ?? false
        pauseItem.image = NSImage(systemSymbolName: isPaused ? "play.circle" : "pause.circle", accessibilityDescription: nil)
        pauseItem.setAccessibilityIdentifier("Command.PauseBlocking")
        menu.addItem(pauseItem)

        let resetItem = NSMenuItem(
            title: localization.menuResetUsage,
            action: #selector(confirmResetUsage),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        resetItem.setAccessibilityIdentifier("Command.ResetUsage")
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        let langMenu = NSMenu()
        let currentOverride = store?.languageOverride ?? .system

        let sysLangItem = NSMenuItem(
            title: localization.languageSystemDefault,
            action: #selector(setLanguageSystem),
            keyEquivalent: ""
        )
        sysLangItem.target = self
        sysLangItem.state = (currentOverride == .system) ? .on : .off
        langMenu.addItem(sysLangItem)

        let koLangItem = NSMenuItem(
            title: "한국어",
            action: #selector(setLanguageKorean),
            keyEquivalent: ""
        )
        koLangItem.target = self
        koLangItem.state = (currentOverride == .ko) ? .on : .off
        langMenu.addItem(koLangItem)

        let enLangItem = NSMenuItem(
            title: "English",
            action: #selector(setLanguageEnglish),
            keyEquivalent: ""
        )
        enLangItem.target = self
        enLangItem.state = (currentOverride == .en) ? .on : .off
        langMenu.addItem(enLangItem)

        let langParentItem = NSMenuItem(title: localization.languageMenuTitle, action: nil, keyEquivalent: "")
        langParentItem.submenu = langMenu
        langParentItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        langParentItem.setAccessibilityIdentifier("Command.SetLanguage")
        menu.addItem(langParentItem)

        let isLaunchAtLogin = loginController.status() == .enabled
        let launchItem = NSMenuItem(
            title: localization.launchAtLoginMenuTitle,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.image = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: nil)
        launchItem.state = isLaunchAtLogin ? .on : .off
        launchItem.setAccessibilityIdentifier("Command.LaunchAtLogin")
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: localization.menuSettings,
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: localization.menuQuit,
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quitItem.setAccessibilityIdentifier("Command.Quit")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        let isBlocked = (snapshot?.protectionState == .limitReached)
        let icon = menuBarImage(for: vm?.usageState ?? .normal, isBlocked: isBlocked)
        statusItem?.button?.image = icon
        statusItem?.button?.imagePosition = .imageLeading
        if let title = vm?.displayTitle {
            statusItem?.button?.title = title
        }
    }

    private func makeMenuBarImage(baseName: String) -> NSImage? {
        let rep1xURL = Bundle.main.url(forResource: "\(baseName)-18", withExtension: "png")
            ?? Bundle.main.url(forResource: "\(baseName)-18", withExtension: "png", subdirectory: "MenuBar")
            ?? URL(fileURLWithPath: "assets/MenuBar/\(baseName)-18.png")
        let rep2xURL = Bundle.main.url(forResource: "\(baseName)-36", withExtension: "png")
            ?? Bundle.main.url(forResource: "\(baseName)-36", withExtension: "png", subdirectory: "MenuBar")
            ?? URL(fileURLWithPath: "assets/MenuBar/\(baseName)-36.png")

        guard let img1x = NSImage(contentsOf: rep1xURL) else { return nil }
        let result = NSImage(size: NSSize(width: 18, height: 18))
        if let rep1 = img1x.representations.first {
            result.addRepresentation(rep1)
        }
        if let img2x = NSImage(contentsOf: rep2xURL), let rep2 = img2x.representations.first {
            rep2.size = NSSize(width: 18, height: 18)
            result.addRepresentation(rep2)
        }
        result.isTemplate = true
        return result
    }

    private func menuBarImage(for state: MenuBarUsageState, isBlocked: Bool) -> NSImage? {
        let baseName: String
        if isBlocked || state == .limitReached {
            baseName = "blocked_template"
        } else {
            switch state {
            case .normal: baseName = "normal_template"
            case .notice: baseName = "notice50_template"
            case .warning: baseName = "warning80_template"
            case .critical: baseName = "critical90_template"
            case .limitReached: baseName = "blocked_template"
            }
        }
        return makeMenuBarImage(baseName: baseName)
    }

    @objc private func togglePauseBlocking() {
        guard let engine else { return }
        Task {
            if let profileID = await engine.currentSnapshot().selectedProfileID {
                let isPaused = await engine.currentSnapshot().isPauseBlockingActive
                _ = try? await engine.pauseBlockingToggled(profileID: profileID, isPaused: !isPaused)
            }
        }
    }

    @objc private func setPresetLimit(_ sender: NSMenuItem) {
        guard let engine, let gb = sender.representedObject as? Double else { return }
        let limitBytes = ByteCount(UInt64(gb * 1_000_000_000.0))
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.selectedProfileID {
                _ = try? await engine.changeLimit(profileID: profileID, newLimitBytes: limitBytes)
            } else if let identity = await engine.currentResolvedIdentity() {
                let name = String(bytes: identity.ssid.bytes, encoding: .utf8) ?? identity.ssid.hex
                _ = try? await engine.createOrUpdateProfile(
                    alias: name,
                    limitBytes: limitBytes,
                    resetDay: 1,
                    interfaceName: identity.interfaceName,
                    ssidHex: identity.ssid.hex,
                    bssid: identity.bssid
                )
            } else {
                openSettingsWindow()
            }
            _ = try? await engine.performPeriodicTick()
        }
    }

    @objc private func setUnlimitedLimit() {
        guard let engine else { return }
        let limitBytes = ByteCount(ProfileRecord.maximumLimitBytes)
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.selectedProfileID {
                _ = try? await engine.changeLimit(profileID: profileID, newLimitBytes: limitBytes)
            } else if let identity = await engine.currentResolvedIdentity() {
                let name = String(bytes: identity.ssid.bytes, encoding: .utf8) ?? identity.ssid.hex
                _ = try? await engine.createOrUpdateProfile(
                    alias: name,
                    limitBytes: limitBytes,
                    resetDay: 1,
                    interfaceName: identity.interfaceName,
                    ssidHex: identity.ssid.hex,
                    bssid: identity.bssid
                )
            } else {
                openSettingsWindow()
            }
            _ = try? await engine.performPeriodicTick()
        }
    }

    @objc private func promptCustomLimit() {
        let alert = NSAlert()
        alert.messageText = localization.promptCustomLimitTitle
        alert.informativeText = localization.promptCustomLimitMessage
        alert.addButton(withTitle: localization.confirm)
        alert.addButton(withTitle: localization.cancel)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        input.placeholderString = localization.promptCustomLimitPlaceholder
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let val = Double(text), val > 0 {
                let limitBytes = ByteCount(UInt64(val * 1_000_000_000.0))
                guard let engine else { return }
                Task {
                    let snapshot = await engine.currentSnapshot()
                    if let profileID = snapshot.selectedProfileID {
                        _ = try? await engine.changeLimit(profileID: profileID, newLimitBytes: limitBytes)
                    } else if let identity = await engine.currentResolvedIdentity() {
                        let name = String(bytes: identity.ssid.bytes, encoding: .utf8) ?? identity.ssid.hex
                        _ = try? await engine.createOrUpdateProfile(
                            alias: name,
                            limitBytes: limitBytes,
                            resetDay: 1,
                            interfaceName: identity.interfaceName,
                            ssidHex: identity.ssid.hex,
                            bssid: identity.bssid
                        )
                    }
                }
            }
        }
    }

    @objc private func setPresetResetDay(_ sender: NSMenuItem) {
        guard let engine, let day = sender.representedObject as? UInt else { return }
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.selectedProfileID {
                _ = try? await engine.changeResetDay(profileID: profileID, newResetDay: day)
            }
        }
    }

    @objc private func promptCustomResetDay() {
        let alert = NSAlert()
        alert.messageText = localization.promptCustomResetDayTitle
        alert.informativeText = localization.promptCustomResetDayMessage
        alert.addButton(withTitle: localization.confirm)
        alert.addButton(withTitle: localization.cancel)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        input.placeholderString = "1 ~ 31"
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let day = UInt(text), (1...31).contains(day) {
                guard let engine else { return }
                Task {
                    let snapshot = await engine.currentSnapshot()
                    if let profileID = snapshot.selectedProfileID {
                        _ = try? await engine.changeResetDay(profileID: profileID, newResetDay: day)
                    }
                }
            }
        }
    }

    @objc private func registerCurrentWiFiAsHotspot() {
        guard let engine else { return }
        Task {
            guard let identity = await engine.currentResolvedIdentity() else {
                openSettingsWindow()
                return
            }
            let ssidStr = String(bytes: identity.ssid.bytes, encoding: .utf8) ?? identity.ssid.hex
            _ = try? await engine.createOrUpdateProfile(
                alias: ssidStr,
                limitBytes: ByteCount(10_000_000_000),
                resetDay: 1,
                interfaceName: identity.interfaceName,
                ssidHex: identity.ssid.hex,
                bssid: identity.bssid
            )
            _ = try? await engine.performPeriodicTick()
        }
    }

    @objc private func openSettingsWindow() {
        guard let engine else { return }
        SettingsWindowController.shared.show(engine: engine, localization: localization)
    }

    @objc private func openLocationSettings() {
        #if canImport(CoreLocation)
        if let manager = locationManager, manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        #endif
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateLanguage(override: StoreLanguageOverrideV1) {
        guard let engine else { return }
        Task {
            _ = try? await engine.setLanguageOverride(override)
            let snapshot = await engine.currentSnapshot()
            let identity = await engine.currentResolvedIdentity()
            let store = await engine.currentStore()
            await MainActor.run {
                self.rebuildMenu(snapshot: snapshot, identity: identity, store: store)
                SettingsWindowController.shared.updateLocalization(self.localization)
            }
        }
    }

    @objc private func setLanguageSystem() {
        updateLanguage(override: .system)
    }

    @objc private func setLanguageKorean() {
        updateLanguage(override: .ko)
    }

    @objc private func setLanguageEnglish() {
        updateLanguage(override: .en)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if loginController.status() == .enabled {
                try loginController.unregister()
            } else {
                try loginController.register()
            }
            guard let engine else { return }
            Task {
                let snapshot = await engine.currentSnapshot()
                let identity = await engine.currentResolvedIdentity()
                let store = await engine.currentStore()
                await MainActor.run {
                    self.rebuildMenu(snapshot: snapshot, identity: identity, store: store)
                }
            }
        } catch {
            fputs("Failed to toggle login item: \(error)\n", stderr)
        }
    }

    @objc private func confirmResetUsage() {
        guard let engine else { return }
        Task {
            if let profileID = await engine.currentSnapshot().selectedProfileID {
                _ = try? await engine.manualResetUsage(profileID: profileID)
            }
        }
    }

    @objc private func quitApp() {
        guard let engine else {
            NSApplication.shared.terminate(nil)
            return
        }
        Task {
            _ = try? await engine.voluntaryQuit()
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func startEngine() {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("HotspotByteFence", isDirectory: true)

            let store = try JournaledStateStore<StoreEnvelopeV1>(directory: appSupport)
            let loadResult = try store.loadEnvelope()
            var envelope: StoreEnvelopeV1
            switch loadResult {
            case .loaded(let env):
                envelope = env
            case .firstRun:
                let initial = try StoreEnvelopeV1.makeInitial(installationID: store.installationID)
                try? store.commitEnvelope(initial, operation: .measurementSample)
                envelope = initial
            case .recoveryRequired:
                if let recovered = try? store.recoverFromLKG() {
                    envelope = recovered
                } else if let stateData = try? Data(contentsOf: appSupport.appendingPathComponent("state.json")),
                          let savedEnv = try? StoreJSONCodec.decode(StoreEnvelopeV1.self, from: stateData) {
                    try? store.commitEnvelope(savedEnv, operation: .measurementSample)
                    envelope = savedEnv
                } else {
                    let initial = try StoreEnvelopeV1.makeInitial(installationID: store.installationID)
                    try? store.commitEnvelope(initial, operation: .measurementSample)
                    envelope = initial
                }
            }

            if envelope.globalState.safetyState == .recoveryRequired {
                let newGlobal = try? GlobalStateRecord(
                    safetyState: .normal,
                    recoveryReason: nil,
                    timeAdjustment: nil,
                    counterCapability: envelope.globalState.counterCapability,
                    identityCapability: envelope.globalState.identityCapability
                )
                if let newGlobal, let normalized = try? envelope.updatingStore(globalState: newGlobal) {
                    try? store.commitEnvelope(normalized, operation: .measurementSample)
                    envelope = normalized
                }
            }

            let counterSource = DarwinInterfaceCounterSource()
            let identitySource = CoreWLANIdentityAdapter()
            let newEngine = RuntimeEngine(
                store: store,
                initialEnvelope: envelope,
                counterSource: counterSource,
                identitySource: identitySource
            )
            self.engine = newEngine

            let snapshots = newEngine.snapshots
            Task { [weak self] in
                await newEngine.startPeriodicPolling(intervalSeconds: 5.0)
                for await snapshot in snapshots {
                    guard let self else { return }
                    let identity = await newEngine.currentResolvedIdentity()
                    let currentStore = await newEngine.currentStore()
                    self.rebuildMenu(snapshot: snapshot, identity: identity, store: currentStore)
                    SettingsWindowController.shared.updateLocalization(self.localization)
                }
            }
        } catch {
            fputs("Failed to initialize runtime engine: \(error)\n", stderr)
        }
    }
}

#if canImport(CoreLocation)
extension AppDelegate: CLLocationManagerDelegate {
    private func setupLocationManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        self.locationManager = manager
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let isAuthorized = (status == .authorizedAlways || status == .authorized)
        Task { @MainActor [weak self] in
            guard let self, let engine = self.engine else { return }
            _ = try? await engine.setLocationPermissionAvailable(isAuthorized)
            _ = try? await engine.performPeriodicTick()
            let snapshot = await engine.currentSnapshot()
            let identity = await engine.currentResolvedIdentity()
            let store = await engine.currentStore()
            self.rebuildMenu(snapshot: snapshot, identity: identity, store: store)
            SettingsWindowController.shared.updateLocalization(self.localization)
        }
    }
}
#endif
#endif

@main
struct HotspotByteFence {
    static func main() throws {
        let args = CommandLine.arguments
       let isJSON = args.contains("--json")

       if args.contains("--manifest") {
            let manifestData = try BuildConfiguration.canonicalJSON(BuildConfiguration.manifest)
            guard let string = String(data: manifestData, encoding: .utf8) else {
                throw BuildManifestError.schemaVersionMismatch
            }
            print(string)
           return
       }

       if args.contains("--manifest-digest") {
            let manifestData = try BuildConfiguration.canonicalJSON(BuildConfiguration.manifest)
            let digest = StoreJSONCodec.sha256Hex(manifestData)
            print(digest)
           return
       }

       if let counterIndex = args.firstIndex(of: "--probe-counter") {
            let remaining = args[(counterIndex + 1)...].filter { $0 != "--json" }
            guard let interface = remaining.first, !interface.isEmpty else {
                fputs("Error: Missing interface for --probe-counter\n", stderr)
                exit(1)
            }
#if canImport(Darwin)
            do {
                let counters = try DarwinInterfaceCounterSource().read(interfaceName: interface)
                if isJSON {
                    let payload: [String: Any] = [
                        "interface": interface,
                        "rx": String(counters.rx),
                        "tx": String(counters.tx),
                        "total": String(counters.total),
                        "available": true
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                } else {
                    print("\(interface) rx=\(counters.rx) tx=\(counters.tx) total=\(counters.total)")
                }
            } catch {
                if isJSON {
                    let payload: [String: Any] = [
                        "interface": interface,
                        "available": false,
                        "error": String(describing: error)
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                } else {
                    fputs("Error reading counters for \(interface): \(error)\n", stderr)
                }
                exit(1)
            }
#else
            if isJSON {
                print("{\"interface\":\"\(interface)\",\"available\":false,\"error\":\"unsupportedPlatform\"}")
            } else {
                fputs("Counter probe is available only on Darwin\n", stderr)
            }
            exit(1)
#endif
           return
       }

       if let continuityIndex = args.firstIndex(of: "--probe-continuity") {
            let remaining = args[(continuityIndex + 1)...].filter { $0 != "--json" }
            guard let interface = remaining.first, !interface.isEmpty else {
                fputs("Error: Missing interface for --probe-continuity\n", stderr)
                exit(1)
            }
            let interval = remaining.count > 1 ? (UInt32(remaining[1]) ?? 1) : 1

#if canImport(Darwin)
            do {
                let counterSource = DarwinInterfaceCounterSource()
                let sample1 = try counterSource.read(interfaceName: interface)
                Thread.sleep(forTimeInterval: TimeInterval(interval))
                let sample2 = try counterSource.read(interfaceName: interface)

                let rxDelta = sample2.rx >= sample1.rx ? sample2.rx - sample1.rx : 0
                let txDelta = sample2.tx >= sample1.tx ? sample2.tx - sample1.tx : 0
                let totalDelta = sample2.total >= sample1.total ? sample2.total - sample1.total : 0
                let continuous = sample2.rx >= sample1.rx && sample2.tx >= sample1.tx && sample2.total >= sample1.total

                if isJSON {
                    let payload: [String: Any] = [
                        "interface": interface,
                        "intervalSeconds": interval,
                        "continuous": continuous,
                        "sample1": [
                            "rx": String(sample1.rx),
                            "tx": String(sample1.tx),
                            "total": String(sample1.total)
                        ],
                        "sample2": [
                            "rx": String(sample2.rx),
                            "tx": String(sample2.tx),
                            "total": String(sample2.total)
                        ],
                        "delta": [
                            "rx": String(rxDelta),
                            "tx": String(txDelta),
                            "total": String(totalDelta)
                        ]
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                } else {
                    print("\(interface) continuous=\(continuous) interval=\(interval)s rxDelta=\(rxDelta) txDelta=\(txDelta) totalDelta=\(totalDelta)")
                }
            } catch {
                if isJSON {
                    let payload: [String: Any] = [
                        "interface": interface,
                        "continuous": false,
                        "error": String(describing: error)
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                } else {
                    fputs("Error probing continuity for \(interface): \(error)\n", stderr)
                }
                exit(1)
            }
#else
            if isJSON {
                print("{\"interface\":\"\(interface)\",\"continuous\":false,\"error\":\"unsupportedPlatform\"}")
            } else {
                fputs("Continuity probe is available only on Darwin\n", stderr)
            }
            exit(1)
#endif
           return
       }

       if args.contains("--probe-identity") {
#if canImport(CoreWLAN)
            do {
                let observations = try CoreWLANIdentityAdapter().readAll()
                var associatedCount = 0
                var unavailableCount = 0
                var interfacesList: [[String: Any]] = []

                for observation in observations {
                    switch observation {
                    case .associated(let snapshot):
                        associatedCount += 1
                        interfacesList.append([
                            "interfaceName": snapshot.interfaceName,
                            "interfaceIndex": snapshot.interfaceIndex,
                            "status": "associated",
                            "isAssociated": true,
                            "ssidHex": snapshot.ssid.hex,
                            "bssid": snapshot.bssid.description
                        ])
                    case .notAssociated(let name, let index):
                        interfacesList.append([
                            "interfaceName": name,
                            "interfaceIndex": index,
                            "status": "notAssociated",
                            "isAssociated": false
                        ])
                    case .identityUnavailable(let name, let index):
                        unavailableCount += 1
                        interfacesList.append([
                            "interfaceName": name,
                            "interfaceIndex": index,
                            "status": "identityUnavailable",
                            "isAssociated": false
                        ])
                    }
                }

                if isJSON {
                    let payload: [String: Any] = [
                        "interfacesCount": observations.count,
                        "associatedCount": associatedCount,
                        "identityUnavailableCount": unavailableCount,
                        "interfaces": interfacesList
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                } else {
                    print("interfaces=\(observations.count) associated=\(associatedCount) identityUnavailable=\(unavailableCount)")
                }
            } catch {
                if isJSON {
                    let payload: [String: Any] = [
                        "interfacesCount": 0,
                        "error": String(describing: error)
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                } else {
                    fputs("Error probing identity: \(error)\n", stderr)
                }
                exit(1)
            }
#else
            if isJSON {
                print("{\"interfacesCount\":0,\"error\":\"unsupportedPlatform\"}")
            } else {
                fputs("Identity probe is available only on CoreWLAN platforms\n", stderr)
            }
            exit(1)
#endif
           return
       }

       if let validateIndex = args.firstIndex(of: "--validate-context") {
            guard validateIndex + 1 < args.count else {
                fputs("Error: Missing context file path for --validate-context\n", stderr)
                exit(1)
            }
            let contextPath = args[validateIndex + 1]

            guard let gateIndex = args.firstIndex(of: "--gate"), gateIndex + 1 < args.count else {
                fputs("Error: Missing --gate argument for --validate-context\n", stderr)
                exit(1)
            }
            let gateID = args[gateIndex + 1]

            guard let caseIndex = args.firstIndex(of: "--case"), caseIndex + 1 < args.count else {
                fputs("Error: Missing --case argument for --validate-context\n", stderr)
                exit(1)
            }
            let caseID = args[caseIndex + 1]

            let contextData = try? Data(contentsOf: URL(fileURLWithPath: contextPath))
            let context: OperatorValidationContextV1? = contextData.flatMap { data in
                try? StoreJSONCodec.decode(OperatorValidationContextV1.self, from: data)
            }

            let execSHA = resolveExecutableSHA256()
            let manifestData = try BuildConfiguration.canonicalJSON(BuildConfiguration.manifest)
            let manifestSHA = StoreJSONCodec.sha256Hex(manifestData)

            let unsignedSHA = context?.digests.unsignedAssetSHA256 ?? execSHA
            let bundleSHA = context?.digests.appBundleSHA256 ?? execSHA

            let candidateDigests = try CandidateDigestSetV1(
                unsignedAssetSHA256: unsignedSHA,
                appBundleSHA256: bundleSHA,
                executableSHA256: execSHA,
                embeddedManifestSHA256: manifestSHA
            )

            let validationResult = OperatorValidationContextValidator.validate(
                context: context,
                candidateDigests: candidateDigests,
                currentGateID: gateID,
                currentCaseID: caseID,
                now: Date()
            )

            if isJSON {
                let payload: [String: Any] = [
                    "gateID": gateID,
                    "caseID": caseID,
                    "validationResult": validationResult.rawValue,
                    "isValid": validationResult == .valid
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } else {
                print("gate=\(gateID) case=\(caseID) result=\(validationResult.rawValue) valid=\(validationResult == .valid)")
            }
           return
       }

       try BuildConfiguration.validate(BuildConfiguration.manifest)
#if canImport(AppKit)
       let isBundleApp = Bundle.main.bundlePath.hasSuffix(".app")
       if isBundleApp || args.contains("--app") {
           let app = NSApplication.shared
           app.setActivationPolicy(.accessory)
           let delegate = AppDelegate()
           app.delegate = delegate
           app.run()
           return
       }
#endif
        print("HotspotByteFence \(BuildConfiguration.manifest.applicationVersion) \(BuildConfiguration.manifest.compiledMode.rawValue)")
    }

    private static func resolveExecutableSHA256() -> String {
        let argv0 = CommandLine.arguments[0]
        let url: URL
        if argv0.hasPrefix("/") {
            url = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
        } else {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(argv0)
                .resolvingSymlinksInPath()
        }
        if let data = try? Data(contentsOf: url) {
            return StoreJSONCodec.sha256Hex(data)
        }
        if let bundleURL = Bundle.main.executableURL?.resolvingSymlinksInPath(),
           let data = try? Data(contentsOf: bundleURL) {
            return StoreJSONCodec.sha256Hex(data)
        }
        return String(repeating: "0", count: 64)
    }
}
