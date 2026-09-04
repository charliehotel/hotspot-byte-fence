import Foundation

public enum MenuBarUsageState: String, Equatable, Sendable {
    case normal
    case notice
    case warning
    case critical
    case limitReached

    public static func from(usageBytes: ByteCount, limitBytes: ByteCount) -> MenuBarUsageState {
        guard limitBytes.rawValue > 0 else { return .normal }
        let ratio = Double(usageBytes.rawValue) / Double(limitBytes.rawValue)
        if ratio >= 1.0 {
            return .limitReached
        } else if ratio >= 0.90 {
            return .critical
        } else if ratio >= 0.80 {
            return .warning
        } else if ratio >= 0.50 {
            return .notice
        } else {
            return .normal
        }
    }
}

public struct MenuBarViewModel: Equatable, Sendable {
    public let displayTitle: String
    public let usageState: MenuBarUsageState
    public let isConnected: Bool
    public let profileName: String?
    public let currentUsageText: String
    public let limitText: String?
    public let percentageText: String?
    public let isPauseBlockingActive: Bool
    public let pauseBlockingToggleTitle: String

    public init(
        snapshot: RuntimeSnapshotV1,
        localization: Localization = Localization()
    ) {
        self.isConnected = (snapshot.connectionState == .monitoring && snapshot.connectedProfileID != nil)
        self.profileName = snapshot.selectedProfileAlias
        self.isPauseBlockingActive = snapshot.isPauseBlockingActive

        if let usage = snapshot.currentUsageBytes, isConnected {
            self.displayTitle = Localization.formatMenuBar(usageBytes: usage, hasResolvedConnection: true)
            self.currentUsageText = UsageFormatter.formatGB(usage)

            if let limit = snapshot.currentLimitBytes, limit.rawValue > 0 {
                self.usageState = MenuBarUsageState.from(usageBytes: usage, limitBytes: limit)
                self.limitText = UsageFormatter.formatGB(limit)

                let ratio = Double(usage.rawValue) / Double(limit.rawValue) * 100.0
                self.percentageText = String(format: "%.1f%%", ratio)
            } else {
                self.usageState = .normal
                self.limitText = nil
                self.percentageText = nil
            }
        } else {
            self.displayTitle = Localization.disconnectedDash
            self.usageState = .normal
            if let usage = snapshot.currentUsageBytes {
                self.currentUsageText = UsageFormatter.formatGB(usage)
            } else {
                self.currentUsageText = Localization.disconnectedDash
            }
            if let limit = snapshot.currentLimitBytes {
                self.limitText = UsageFormatter.formatGB(limit)
            } else {
                self.limitText = nil
            }
            self.percentageText = nil
        }

        self.pauseBlockingToggleTitle = snapshot.isPauseBlockingActive
            ? localization.menuResumeBlocking
            : localization.menuPauseBlocking
    }
}
