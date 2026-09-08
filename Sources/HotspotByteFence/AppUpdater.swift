import AppKit
import Foundation
import HotspotByteFenceCore

@MainActor
final class AppUpdater {
    var localization = Localization()
    var onChange: (() -> Void)?
    var onInstall: (() async throws -> Void)?
    private(set) var release: AppRelease?
    private(set) var busy = false
    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let releasesURL = URL(string: "https://github.com/charliehotel/hotspot-byte-fence/releases")!
    private let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? BuildConfiguration.manifest.applicationVersion
    private var korean: Bool { localization.effectiveLanguage == .korean }

    var menuTitle: String {
        if busy { return korean ? "업데이트 확인·준비 중…" : "Checking / Preparing Update…" }
        if let release {
            return korean ? "업데이트 확인… (\(release.tag_name) 새 버전)" : "Check for Updates… (\(release.tag_name) Available)"
        }
        return korean ? "업데이트 확인…" : "Check for Updates…"
    }

    func start() {
        if let data = defaults.data(forKey: "updates.release"),
           let cached = try? JSONDecoder().decode(AppRelease.self, from: data),
           cached.isNewer(than: currentVersion) { release = cached }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        checkIfDue()
    }

    private func checkIfDue() {
        guard AppUpdatePolicy.shouldCheck(now: Date(), lastAttempt: defaults.object(forKey: "updates.lastAttempt") as? Date) else { return }
        Task { await check(manual: false) }
    }

    func check(manual: Bool) async {
        guard !busy else { return }
        busy = true
        onChange?()
        defer { busy = false; onChange?() }
        defaults.set(Date(), forKey: "updates.lastAttempt")
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/charliehotel/hotspot-byte-fence/releases/latest")!, timeoutInterval: 20)
            request.setValue("HotspotByteFence", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw failure("Invalid response") }
            if http.statusCode == 404 {
                release = nil
                defaults.removeObject(forKey: "updates.release")
                if manual { message(korean ? "공개 릴리스를 찾을 수 없습니다." : "No public release was found.", korean ? "아직 배포되지 않았거나 저장소에 접근할 수 없습니다." : "The app may not have been released yet, or the repository is unavailable.") }
                return
            }
            guard http.statusCode == 200 else { throw failure("GitHub HTTP \(http.statusCode)") }
            let latest = try JSONDecoder().decode(AppRelease.self, from: data)
            guard ReleaseVersion(latest.tag_name) != nil else { throw failure("Invalid release version") }
            release = latest.isNewer(than: currentVersion) ? latest : nil
            if let release { defaults.set(try JSONEncoder().encode(release), forKey: "updates.release") }
            else { defaults.removeObject(forKey: "updates.release") }
            guard manual else { return }
            guard let release else {
                message(korean ? "최신 버전을 사용하고 있습니다." : "You’re up to date.", "Hotspot Byte Fence v\(currentVersion)")
                return
            }
            let alert = NSAlert()
            alert.messageText = korean ? "\(release.tag_name) 새 버전이 있습니다." : "\(release.tag_name) is available."
            alert.informativeText = korean ? "현재 버전: v\(currentVersion)\n업데이트를 다운로드하시겠습니까? 다운로드 후 설치 전에 다시 확인합니다." : "Current version: v\(currentVersion)\nDownload the update? Installation requires a separate confirmation."
            alert.addButton(withTitle: korean ? "다운로드" : "Download")
            alert.addButton(withTitle: korean ? "나중에" : "Later")
            alert.addButton(withTitle: korean ? "릴리스 보기" : "View Release")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn: try await downloadAndInstall(release)
            case .alertThirdButtonReturn: NSWorkspace.shared.open(releasesURL)
            default: break
            }
        } catch {
            if manual { message(korean ? "업데이트를 완료하지 못했습니다." : "Unable to complete the update.", error.localizedDescription) }
        }
    }

    private func downloadAndInstall(_ release: AppRelease) async throws {
        guard let asset = release.installAsset else {
            message(korean ? "자동 설치용 파일을 확인할 수 없습니다." : "No verified installation asset is available.", korean ? "공식 ZIP 또는 SHA-256 정보가 없습니다. 릴리스 페이지의 설치 안내를 확인해 주세요." : "The official ZIP or SHA-256 digest is missing. Follow the release page’s installation instructions.")
            NSWorkspace.shared.open(releasesURL)
            return
        }
        let target = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard target.pathExtension == "app", FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw failure(korean ? "현재 앱 폴더에 쓰기 권한이 없습니다. 쓰기 가능한 폴더로 앱을 옮긴 뒤 다시 시도해 주세요." : "The app folder is not writable. Move the app to a writable folder and try again.")
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("HotspotByteFence-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: work) }
        var request = URLRequest(url: asset.browser_download_url, timeoutInterval: 120)
        request.setValue("HotspotByteFence", forHTTPHeaderField: "User-Agent")
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Download failed") }
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        guard data.count == asset.size,
              "sha256:" + StoreJSONCodec.sha256Hex(data) == asset.digest?.lowercased() else { throw failure("SHA-256 / size mismatch") }
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: download, to: zip)
        let listing = try await run("/usr/bin/unzip", ["-Z1", zip.path])
        guard AppUpdatePolicy.safeArchivePaths(listing) else { throw failure("Unsafe archive paths") }
        let details = try await run("/usr/bin/zipinfo", ["-l", zip.path])
        guard !details.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) else { throw failure("Archive contains symbolic links") }
        _ = try await run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let app = work.appendingPathComponent("HotspotByteFence.app")
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == BuildManifestV1.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              ReleaseVersion(version) == ReleaseVersion(release.tag_name),
              bundle.executableURL?.lastPathComponent == "HotspotByteFence" else { throw failure("App identity / version mismatch") }
        _ = try await run("/usr/bin/codesign", ["-s", "-", "--force", "--deep", app.path])
        _ = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let alert = NSAlert()
        alert.messageText = korean ? "\(release.tag_name)을 설치하고 다시 시작할까요?" : "Install \(release.tag_name) and restart?"
        alert.informativeText = korean
            ? "설치 위치: \(target.path)\n기존 앱은 새 앱의 실행 요청이 성공하면 휴지통으로 옮깁니다. 이동에 실패하면 설치 폴더에 백업을 보존합니다. 프로필·사용량은 유지합니다. 앱을 종료한 동안에는 측정과 차단이 중단됩니다. 로컬 서명이 변경되어 위치·알림 권한을 다시 허용해야 할 수 있습니다."
            : "Install at: \(target.path)\nThe previous app moves to Trash after the new app’s launch request succeeds. If moving it fails, the backup stays in the installation folder. Profiles and usage are preserved. Monitoring and blocking stop while the app is closed. Local signing may require granting location and notification permissions again."
        alert.addButton(withTitle: korean ? "설치 및 다시 시작" : "Install and Restart")
        alert.addButton(withTitle: korean ? "취소" : "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let staged = target.deletingLastPathComponent().appendingPathComponent(".HotspotByteFence-update-\(UUID().uuidString).app")
        try FileManager.default.copyItem(at: app, to: staged)
        let backup = target.deletingLastPathComponent().appendingPathComponent("HotspotByteFence-backup-\(UUID().uuidString).app")
        do {
            // The helper uses positional arguments, never interpolated shell paths. Keep the backup until the launch request succeeds.
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = ["-c", AppUpdatePolicy.installScript, "hbf-update", String(ProcessInfo.processInfo.processIdentifier), staged.path, target.path, backup.path]
            helper.standardOutput = FileHandle.nullDevice
            helper.standardError = FileHandle.nullDevice
            try helper.run()
            do {
                try await onInstall?()
            } catch {
                helper.terminate()
                helper.waitUntilExit()
                throw error
            }
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    private func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "AppUpdate", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    private func failure(_ description: String) -> Error {
        NSError(domain: "AppUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func message(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: korean ? "확인" : "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
