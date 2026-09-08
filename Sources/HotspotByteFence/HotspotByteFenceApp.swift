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
import SwiftUI
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var engine: RuntimeEngine?
    private var localization = Localization()
    private let loginController: LoginItemControlling = DarwinLoginItemController()
    private let notificationDelivery: NotificationDeliverySource = DarwinNotificationDelivery()
    private var usageNotificationTracker = UsageNotificationTracker()
    private var promptedNetwork: WiFiIdentitySnapshot?
    private var automaticProfileActivationDetector = AutomaticProfileActivationDetector()
    private let updater = AppUpdater()
    private var aboutWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private let profileManagement = ProfileManagementState()
#if canImport(CoreLocation)
    private var locationManager: CLLocationManager?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        if CommandLine.arguments.contains("--preview-ui") {
            NSApp.setActivationPolicy(.regular)
            updater.onChange = { [weak self] in self?.refreshUpdateMenuItem() }
            if CommandLine.arguments.contains("--preview-settings") {
                openSettingsWindow()
            } else {
                openAboutWindow()
            }
            if CommandLine.arguments.contains("--preview-menu") {
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window = self.aboutWindow ?? self.preferencesWindow else { return }
                    self.statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 40, y: 80), in: window.contentView)
                }
            }
            return
        }
#if canImport(CoreLocation)
        setupLocationManager()
#endif
        startEngine()
        updater.onChange = { [weak self] in self?.refreshUpdateMenuItem() }
        updater.onInstall = { [weak self] in
            guard let engine = self?.engine else { return }
            do {
                _ = try await engine.voluntaryQuit()
            } catch {
                await engine.startPeriodicPolling(intervalSeconds: 5.0)
                throw error
            }
        }
        updater.start()
#if canImport(UserNotifications)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
#endif
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = Localization.disconnectedDash
        statusItem?.button?.setAccessibilityIdentifier("MenuBar.UsageValue")
        rebuildMenu(snapshot: nil, identity: nil, store: nil)
    }

    private func rebuildMenu(snapshot: RuntimeSnapshotV1?, identity: WiFiIdentitySnapshot?, store: StoreEnvelopeV1?) {
        if let store, let snapshot { profileManagement.update(store: store, snapshot: snapshot) }
        let appLang: AppLanguage
        switch store?.languageOverride {
        case .ko: appLang = .korean
        case .en: appLang = .english
        default: appLang = .systemDefault
        }
        self.localization = Localization(language: appLang)
        updater.localization = localization

        let menu = NSMenu()
        menu.autoenablesItems = false
        let vm = snapshot.map { MenuBarViewModel(snapshot: $0, localization: localization) }

        let headerItem = NSMenuItem(title: "Hotspot Byte Fence", action: #selector(openAboutWindow), keyEquivalent: "")
        headerItem.target = self
        headerItem.setAccessibilityIdentifier("Command.About")
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

        let wifiItem = NSMenuItem(title: "Wi-Fi: \(wifiName) (\(statusText))", action: nil, keyEquivalent: "")
        wifiItem.isEnabled = true
        wifiItem.image = NSImage(systemSymbolName: identity != nil ? "wifi" : "wifi.slash", accessibilityDescription: nil)
        wifiItem.view = MonitoringStatusMenuView(title: wifiItem.title, image: wifiItem.image)
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
        let currentProfileID = snapshot?.connectedProfileID ?? snapshot?.selectedProfileID
        let usageItem = NSMenuItem(title: "\(localization.menuUsagePrefix) \(usageTitle) / \(limitTitle)\(percentStr)", action: #selector(editUsageMenuItem(_:)), keyEquivalent: "")
        usageItem.target = self
        usageItem.representedObject = currentProfileID
        usageItem.isEnabled = currentProfileID != nil
        usageItem.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
        usageItem.setAccessibilityIdentifier("Status.Measurement")
        menu.addItem(usageItem)

        if let profileID = currentProfileID,
           let profile = store?.profiles.first(where: { $0.profileID == profileID }) {
            let resetItem = NSMenuItem(title: localization.formatResetDay(day: profile.resetDay), action: #selector(editResetDayMenuItem(_:)), keyEquivalent: "")
            resetItem.target = self
            resetItem.representedObject = profileID
            resetItem.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            menu.addItem(resetItem)
        }

        let profilesMenu = NSMenu()
        profilesMenu.autoenablesItems = false
        let registerProfileItem = NSMenuItem(
            title: localization.menuRegisterProfileTitle,
            action: #selector(registerProfileMenuItem),
            keyEquivalent: ""
        )
        registerProfileItem.target = self
        registerProfileItem.setAccessibilityIdentifier("Command.RegisterProfile")
        profilesMenu.addItem(registerProfileItem)
        profilesMenu.addItem(NSMenuItem.separator())

        let profiles = store?.profiles ?? []
        if profiles.isEmpty {
            let emptyProfilesItem = NSMenuItem(
                title: localization.menuNoProfilesRegistered,
                action: nil,
                keyEquivalent: ""
            )
            emptyProfilesItem.isEnabled = false
            profilesMenu.addItem(emptyProfilesItem)
        } else {
            let activeProfileID = snapshot?.selectedProfileID ?? snapshot?.connectedProfileID
            for profile in profiles {
                let profileItem = NSMenuItem(title: profile.aliasNFC, action: nil, keyEquivalent: "")
                profileItem.state = profile.profileID == activeProfileID ? .on : .off
                profileItem.setAccessibilityIdentifier("Menu.Profile.\(profile.profileID.uuidString)")
                let actions = NSMenu()
                let selectItem = NSMenuItem(title: localization.effectiveLanguage == .korean ? "선택" : "Select", action: #selector(selectProfileMenuItem(_:)), keyEquivalent: "")
                selectItem.target = self
                selectItem.representedObject = profile.profileID
                selectItem.state = profileItem.state
                actions.addItem(selectItem)
                let editItem = NSMenuItem(title: localization.effectiveLanguage == .korean ? "편집" : "Edit", action: #selector(editProfileMenuItem(_:)), keyEquivalent: "")
                editItem.target = self
                editItem.representedObject = profile.profileID
                actions.addItem(editItem)
                profileItem.submenu = actions
                profilesMenu.addItem(profileItem)
            }

        }

        profilesMenu.addItem(.separator())
        let manageItem = NSMenuItem(title: localization.effectiveLanguage == .korean ? "프로필 관리…" : "Manage Profiles…",
                                   action: #selector(openProfileManagement), keyEquivalent: "")
        manageItem.target = self
        profilesMenu.addItem(manageItem)

        let profilesParentItem = NSMenuItem(
            title: localization.menuProfilesTitle,
            action: nil,
            keyEquivalent: ""
        )
        profilesParentItem.submenu = profilesMenu
        profilesParentItem.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
        profilesParentItem.setAccessibilityIdentifier("Command.Profiles")
        menu.addItem(profilesParentItem)

        if let identity, snapshot?.connectedProfileID == nil {
            let ssidBytes = identity.ssid.bytes
            let ssidStr = String(bytes: ssidBytes, encoding: .utf8) ?? identity.ssid.hex
            let registerItem = NSMenuItem(
                title: snapshot?.connectionState == .needsBSSIDConfirmation
                    ? localization.confirmExistingHotspotTitle
                    : localization.formatRegisterHotspot(ssid: ssidStr),
                action: snapshot?.connectionState == .needsBSSIDConfirmation
                    ? #selector(confirmCurrentHotspot) : #selector(registerCurrentWiFiAsHotspot),
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
        menu.addItem(NSMenuItem.separator())

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

        let settingsItem = NSMenuItem(
            title: localization.menuSettings,
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: updater.menuTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = !updater.busy
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        updateItem.setAccessibilityIdentifier("Command.CheckForUpdates")
        menu.addItem(updateItem)

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
            statusItem?.button?.title = (snapshot?.isPauseBlockingActive == true ? "⏸ " : "") + title
        }
    }

    private func refreshUpdateMenuItem() {
        guard let item = statusItem?.menu?.items.first(where: { $0.action == #selector(checkForUpdates) }) else { return }
        item.title = updater.menuTitle
        item.isEnabled = !updater.busy
    }

    @objc private func checkForUpdates() {
        Task { await updater.check(manual: true) }
    }

    @objc private func openAboutWindow() {
        let screen = aboutWindow?.screen ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? NSSize(width: 1024, height: 768)
        var width = min(520, available.width - 40)
        let controller = NSHostingController(rootView: AppInformationView(localization: localization, width: width))
        while controller.view.fittingSize.height > available.height - 60 && width < available.width - 40 {
            width = min(width + 40, available.width - 40)
            controller.rootView = AppInformationView(localization: localization, width: width)
            controller.view.layoutSubtreeIfNeeded()
        }
        let window = aboutWindow ?? NSWindow(contentViewController: controller)
        window.contentViewController = controller
        window.title = localization.effectiveLanguage == .korean ? "Hotspot Byte Fence 정보" : "About Hotspot Byte Fence"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.fittingSize)
        if aboutWindow == nil { window.center() }
        aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMenuBarImage(baseName: String, isTemplate: Bool = true) -> NSImage? {
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
        result.isTemplate = isTemplate
        return result
    }

    private func menuBarImage(for state: MenuBarUsageState, isBlocked: Bool) -> NSImage? {
        let baseName: String
        let useTemplate: Bool
        if isBlocked || state == .limitReached {
            baseName = "blocked"
            useTemplate = false
        } else {
            switch state {
            case .normal: baseName = "normal"; useTemplate = false
            case .notice: baseName = "notice50"; useTemplate = false
            case .warning: baseName = "warning80"; useTemplate = false
            case .critical: baseName = "critical90"; useTemplate = false
            case .limitReached: baseName = "blocked"; useTemplate = false
            }
        }
        return makeMenuBarImage(baseName: baseName, isTemplate: useTemplate)
    }

    @objc private func togglePauseBlocking() {
        guard let engine else { return }
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.connectedProfileID ?? snapshot.selectedProfileID {
                let isPaused = await engine.currentSnapshot().isPauseBlockingActive
                _ = try? await engine.pauseBlockingToggled(profileID: profileID, isPaused: !isPaused)
            }
        }
    }

    @objc private func selectProfileMenuItem(_ sender: NSMenuItem) {
        guard let engine, let profileID = sender.representedObject as? UUID else { return }
        Task {
            _ = try? await engine.selectProfile(id: profileID)
        }
    }

    @objc private func registerProfileMenuItem() {
        guard let engine else { return }
        SettingsWindowController.shared.show(
            engine: engine,
            localization: localization,
            registeringProfile: true
        )
    }

    @objc private func editProfileMenuItem(_ sender: NSMenuItem) {
        guard let engine, let profileID = sender.representedObject as? UUID else { return }
        SettingsWindowController.shared.show(engine: engine, localization: localization, profileID: profileID)
    }

    @objc private func editUsageMenuItem(_ sender: NSMenuItem) {
        guard let engine, let profileID = sender.representedObject as? UUID else { return }
        SettingsWindowController.shared.show(engine: engine, localization: localization, profileID: profileID)
    }

    @objc private func editResetDayMenuItem(_ sender: NSMenuItem) {
        guard let engine, let profileID = sender.representedObject as? UUID else { return }
        SettingsWindowController.shared.show(engine: engine, localization: localization, profileID: profileID)
    }

    @objc private func setPresetLimit(_ sender: NSMenuItem) {
        guard let engine, let gb = sender.representedObject as? Double else { return }
        let limitBytes = ByteCount(UInt64(gb * 1_000_000_000.0))
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.connectedProfileID ?? snapshot.selectedProfileID {
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
            SettingsWindowController.shared.show(engine: engine, localization: localization)
            }
            _ = try? await engine.performPeriodicTick()
        }
    }

    @objc private func setUnlimitedLimit() {
        guard let engine else { return }
        let limitBytes = ByteCount(ProfileRecord.maximumLimitBytes)
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.connectedProfileID ?? snapshot.selectedProfileID {
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
                    if let profileID = snapshot.connectedProfileID ?? snapshot.selectedProfileID {
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
                    _ = try? await engine.performPeriodicTick()
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

    @objc private func openProfileManagement() {
        profileManagement.tab = 1
        openSettingsWindow()
    }

    @objc private func openSettingsWindow() {
        let locationGranted: Bool
#if canImport(CoreLocation)
        let locationStatus = locationManager?.authorizationStatus
        locationGranted = locationStatus == .authorized || locationStatus == .authorizedAlways
#else
        locationGranted = false
#endif
        let view = PreferencesView(profileManagement: profileManagement, editProfile: { [weak self] id in
            guard let self, let engine = self.engine else { return }
            SettingsWindowController.shared.show(engine: engine, localization: self.localization, profileID: id)
        }, registerProfile: { [weak self] in self?.registerProfileMenuItem() }, localization: localization, language: { [weak self] value in self?.updateLanguage(override: value) }, toggleLaunch: { [weak self] in self?.toggleLaunchAtLogin() }, launchEnabled: loginController.status() == .enabled, locationGranted: locationGranted, openLocation: { [weak self] in self?.openLocationSettings() })
        let controller = NSHostingController(rootView: view)
        let window = preferencesWindow ?? NSWindow(contentViewController: controller)
        window.contentViewController = controller
        window.title = localization.settingsWindowTitle
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.view.fittingSize)
        if preferencesWindow == nil { window.center() }
        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
                if self.preferencesWindow?.isVisible == true { self.openSettingsWindow() }
                if self.aboutWindow?.isVisible == true { self.openAboutWindow() }
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
                    if self.preferencesWindow?.isVisible == true { self.openSettingsWindow() }
                }
            }
        } catch {
            fputs("Failed to toggle login item: \(error)\n", stderr)
        }
    }

    @objc private func confirmResetUsage() {
        guard let engine else { return }
        let alert = NSAlert()
        alert.messageText = localization.manualResetTitle
        alert.informativeText = localization.manualResetMessage
        alert.addButton(withTitle: localization.confirm)
        alert.addButton(withTitle: localization.cancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            let snapshot = await engine.currentSnapshot()
            if let profileID = snapshot.connectedProfileID ?? snapshot.selectedProfileID {
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
            let newEngine = RuntimeEngine(store: store, initialEnvelope: envelope)
            self.engine = newEngine
            self.profileManagement.engine = newEngine

            let snapshots = newEngine.snapshots
            Task { [weak self] in
                await newEngine.startPeriodicPolling(intervalSeconds: 5.0)
                for await snapshot in snapshots {
                    guard let self else { return }
                    let identity = await newEngine.currentResolvedIdentity()
                    let currentStore = await newEngine.currentStore()
                    self.rebuildMenu(snapshot: snapshot, identity: identity, store: currentStore)
                    SettingsWindowController.shared.updateLocalization(self.localization)
                    await self.handleAutomaticProfileNotification(snapshot: snapshot, identity: identity, store: currentStore)
                    await self.offerProfileRegistration(identity: identity, engine: newEngine)
                    await self.handleUsageNotifications(snapshot: snapshot, store: currentStore)
                }
            }
        } catch {
            fputs("Failed to initialize runtime engine: \(error)\n", stderr)
        }
    }

    @objc private func confirmCurrentHotspot() {
        guard let engine else { return }
        Task {
            promptedNetwork = nil
            await offerProfileRegistration(identity: await engine.currentResolvedIdentity(), engine: engine)
        }
    }

    private func offerProfileRegistration(identity: WiFiIdentitySnapshot?, engine: RuntimeEngine) async {
        guard let identity else {
            promptedNetwork = nil
            return
        }
        guard promptedNetwork != identity else { return }
        let snapshot = await engine.currentSnapshot()
        guard snapshot.connectionState == .unknownNetwork || snapshot.connectionState == .needsBSSIDConfirmation else { return }
        promptedNetwork = identity
        if snapshot.connectionState == .needsBSSIDConfirmation {
            let profiles = await engine.currentStore().profiles.filter {
                $0.isComplete && $0.interfaceName == identity.interfaceName && $0.ssidHex == identity.ssid.hex
            }
            guard !profiles.isEmpty else { return }
            let alert = NSAlert()
            alert.messageText = localization.confirmExistingHotspotTitle
            alert.informativeText = localization.changedHotspotExplanation
            let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
            for profile in profiles { choices.addItem(withTitle: profile.aliasNFC) }
            alert.accessoryView = choices
            alert.addButton(withTitle: localization.continueExistingProfileTitle)
            alert.addButton(withTitle: localization.cancel)
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn,
                  profiles.indices.contains(choices.indexOfSelectedItem) else { return }
            do {
                // Refresh the observed connection after the modal before accepting its address.
                _ = try await engine.performPeriodicTick()
                guard await engine.currentResolvedIdentity() == identity else { return }
                try await engine.confirmBSSID(profileID: profiles[choices.indexOfSelectedItem].profileID, bssid: identity.bssid)
            } catch {
                NSAlert(error: error).runModal()
            }
            return
        }
        guard snapshot.connectionState == .unknownNetwork,
              await engine.currentResolvedIdentity() == identity else { return }
        let ssid = String(bytes: identity.ssid.bytes, encoding: .utf8) ?? identity.ssid.hex
        let alert = NSAlert()
        alert.messageText = localization.newNetworkProfilePrompt(ssid: ssid)
        alert.informativeText = localization.newNetworkProfileExplanation
        alert.addButton(withTitle: localization.menuRegisterProfileTitle)
        alert.addButton(withTitle: localization.profileSetupLaterTitle)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              await engine.currentResolvedIdentity() == identity else { return }
        registerProfileMenuItem()
    }

#if canImport(UserNotifications)
    private func handleAutomaticProfileNotification(
        snapshot: RuntimeSnapshotV1,
        identity: WiFiIdentitySnapshot?,
        store: StoreEnvelopeV1
    ) async {
        guard let profileID = automaticProfileActivationDetector.profileIDToNotify(
            snapshot: snapshot,
            identity: identity
        ),
              let profile = store.profiles.first(where: { $0.profileID == profileID }) else {
            return
        }
        try? await notificationDelivery.deliver(
            title: localization.profileActivatedNotificationTitle(profileName: profile.aliasNFC),
            body: localization.profileActivatedNotificationBody(profileName: profile.aliasNFC),
            category: .profileActivated
        )
    }
#endif

#if canImport(UserNotifications)
    private func handleUsageNotifications(
        snapshot: RuntimeSnapshotV1,
        store: StoreEnvelopeV1
    ) async {
        guard let usage = snapshot.currentUsageBytes,
              let limit = snapshot.currentLimitBytes,
              limit.rawValue > 0, limit.rawValue < ProfileRecord.maximumLimitBytes,
              let profileID = snapshot.connectedProfileID ?? snapshot.selectedProfileID,
              let profile = store.profiles.first(where: { $0.profileID == profileID }) else {
            return
        }
        let percent = Double(usage.rawValue) / Double(limit.rawValue) * 100.0
        let alias = profile.aliasNFC
        let limitText = UsageFormatter.formatGB(limit)
        let cycleDate = profile.cycle.cycleID.effectiveDate
        let categories = usageNotificationTracker.observe(
            profileID: profileID, cycle: cycleDate, percent: percent,
            protection: snapshot.protectionState, paused: snapshot.isPauseBlockingActive,
            enabledThresholds: Set(NotificationPreference.allCases.filter { $0.isEnabled() })
        )
        for category in categories {
            let title: String
            let body: String
            switch category {
            case .limitReached:
                title = localization.limitReachedNotificationTitle(profileName: alias)
                body = localization.limitReachedNotificationBody(profileName: alias, limitGB: limitText)
            case .blockingFailed:
                title = localization.blockingFailedNotificationTitle(profileName: alias)
                body = localization.effectiveLanguage == .korean
                    ? "네트워크 차단을 완료하지 못했습니다. Wi-Fi 연결과 사용량을 확인해 주세요."
                    : "Network blocking could not be completed. Check your Wi-Fi connection and data usage."
            case .usage50, .usage80, .warningThreshold:
                let threshold = category == .usage50 ? 50 : category == .usage80 ? 80 : 90
                title = localization.warningThresholdNotificationTitle(profileName: alias, percent: threshold)
                body = localization.warningThresholdNotificationBody(profileName: alias, limitGB: limitText, percent: threshold)
            case .profileActivated:
                continue
            }
            do {
                try await notificationDelivery.deliver(title: title, body: body, category: category)
            } catch {
                fputs("Failed to deliver usage notification: \(error)\n", stderr)
            }
        }
    }
#endif
}

@MainActor
private final class MonitoringStatusMenuView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    init(title: String, image: NSImage?) {
        super.init(frame: .zero)
        autoresizingMask = [.width]
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        let icon = NSImageView()
        icon.image = image
        icon.contentTintColor = .labelColor
        let row = NSStackView(views: [icon, label])
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setFrameSize(NSSize(width: label.fittingSize.width + 58, height: 24))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }
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
            if self.preferencesWindow?.isVisible == true { self.openSettingsWindow() }
        }
    }
}
#endif
#endif

@main
struct HotspotByteFence {
    @MainActor static func main() throws {
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
