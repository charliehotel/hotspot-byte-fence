import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum NotificationCategory: String, Sendable {
    case limitReached
    case blockingFailed
    case warningThreshold
    case profileActivated
    case usage50
    case usage80

    public var preference: NotificationPreference {
        switch self {
        case .profileActivated: return .automaticProfileChange
        case .limitReached, .blockingFailed: return .networkBlocking
        case .usage50: return .usage50
        case .usage80: return .usage80
        case .warningThreshold: return .usage90
        }
    }
}

public enum NotificationPreference: String, CaseIterable, Sendable {
    case automaticProfileChange, networkBlocking, usage50, usage80, usage90

    public var key: String { "notifications.enabled.\(rawValue)" }

    public func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

public struct UsageNotificationTracker: Sendable {
    private var observations: [UUID: (cycle: String, percent: Double, protection: ProtectionState)] = [:]

    public init() {}

    public mutating func observe(profileID: UUID, cycle: String, percent: Double,
                                 protection: ProtectionState, paused: Bool,
                                 enabledThresholds: Set<NotificationPreference> = [.usage50, .usage80, .usage90]) -> [NotificationCategory] {
        let previous = observations[profileID]
        let previousPercent = previous?.cycle == cycle && percent >= (previous?.percent ?? 0)
            ? previous?.percent ?? 0 : 0
        observations[profileID] = (cycle, percent, protection)
        if !paused, protection == .blockingFailed,
           previous?.cycle != cycle || previous?.protection != .blockingFailed {
            return [.blockingFailed]
        }
        if !paused, protection == .limitReached,
           previous?.cycle != cycle || previous?.protection != .limitReached {
            return [.limitReached]
        }
        if percent >= 100 { return [] }
        if percent >= 90 && previousPercent < 90 && enabledThresholds.contains(.usage90) { return [.warningThreshold] }
        if percent >= 80 && previousPercent < 80 && enabledThresholds.contains(.usage80) { return [.usage80] }
        if percent >= 50 && previousPercent < 50 && enabledThresholds.contains(.usage50) { return [.usage50] }
        return []
    }
}

public struct AutomaticProfileActivationDetector: Sendable {
    private var hasObservedState = false
    private var lastIdentity: WiFiIdentitySnapshot?
    private var lastProfileID: UUID?
    private var networkChangePending = false

    public init() {}

    public mutating func profileIDToNotify(
        snapshot: RuntimeSnapshotV1,
        identity: WiFiIdentitySnapshot?
    ) -> UUID? {
        if hasObservedState, identity != lastIdentity {
            networkChangePending = true
        }

        let profileID = snapshot.connectedProfileID
        let shouldNotify = networkChangePending && identity != nil && profileID != nil && profileID != lastProfileID

        hasObservedState = true
        lastIdentity = identity
        lastProfileID = profileID

        guard shouldNotify else { return nil }
        networkChangePending = false
        return profileID
    }
}

public enum NotificationSuppressionReason: String, Equatable, Sendable {
    case alreadyNotifiedInCycle
    case mutedUntilInstant
    case mutedUntilCycleEnds
    case throttledMinInterval
}

public enum NotificationEvaluationOutcome: Equatable, Sendable {
    case deliver(updatedRecord: ProfileNotificationRecord)
    case suppressed(reason: NotificationSuppressionReason)
}

public protocol NotificationDeliverySource: Sendable {
    func deliver(title: String, body: String, category: NotificationCategory) async throws
}

public struct NotificationEvaluator: Sendable {
    public static let minFailureIntervalSeconds: TimeInterval = 300
    public static let mute10MinutesSeconds: TimeInterval = 600
    public static let mute1HourSeconds: TimeInterval = 3600

    public static func shouldNotifyLimitReached(
        isPauseBlockingActive: Bool,
        protectionState: ProtectionState,
        usagePercent: Double,
        lastNotifiedPercent: Double
    ) -> Bool {
        !isPauseBlockingActive &&
        (protectionState == .limitReached || usagePercent >= 100) &&
        lastNotifiedPercent < 100
    }

    public static func evaluateLimitReached(
        record: ProfileNotificationRecord,
        currentCycleDate: String
    ) throws -> NotificationEvaluationOutcome {
        if record.successNotifiedCycleDate == currentCycleDate {
            return .suppressed(reason: .alreadyNotifiedInCycle)
        }

        let updated = try ProfileNotificationRecord(
            successNotifiedCycleDate: currentCycleDate,
            failureMute: record.failureMute,
            muteExpiresAt: record.muteExpiresAt,
            muteCycleDate: record.muteCycleDate,
            lastFailureNotificationAt: record.lastFailureNotificationAt
        )
        return .deliver(updatedRecord: updated)
    }

    public static func evaluateBlockingFailed(
        record: ProfileNotificationRecord,
        now: Date,
        currentCycleDate: String
    ) throws -> NotificationEvaluationOutcome {
        switch record.failureMute {
        case .none:
            break
        case .untilInstant:
            if let expires = record.muteExpiresAt, now < expires {
                return .suppressed(reason: .mutedUntilInstant)
            }
        case .untilCycleEnds:
            if record.muteCycleDate == currentCycleDate {
                return .suppressed(reason: .mutedUntilCycleEnds)
            }
        }

        if let last = record.lastFailureNotificationAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 0 && elapsed < minFailureIntervalSeconds {
                return .suppressed(reason: .throttledMinInterval)
            }
        }

        let updated = try ProfileNotificationRecord(
            successNotifiedCycleDate: record.successNotifiedCycleDate,
            failureMute: .none,
            muteExpiresAt: nil,
            muteCycleDate: nil,
            lastFailureNotificationAt: now
        )
        return .deliver(updatedRecord: updated)
    }

    public static func applyMute(
        record: ProfileNotificationRecord,
        duration: ProfileFailureMuteV1,
        now: Date,
        currentCycleDate: String
    ) throws -> ProfileNotificationRecord {
        switch duration {
        case .none:
            return try ProfileNotificationRecord(
                successNotifiedCycleDate: record.successNotifiedCycleDate,
                failureMute: .none,
                muteExpiresAt: nil,
                muteCycleDate: nil,
                lastFailureNotificationAt: record.lastFailureNotificationAt
            )
        case .untilInstant:
            let expiresAt = now.addingTimeInterval(mute10MinutesSeconds)
            return try ProfileNotificationRecord(
                successNotifiedCycleDate: record.successNotifiedCycleDate,
                failureMute: .untilInstant,
                muteExpiresAt: expiresAt,
                muteCycleDate: nil,
                lastFailureNotificationAt: record.lastFailureNotificationAt
            )
        case .untilCycleEnds:
            return try ProfileNotificationRecord(
                successNotifiedCycleDate: record.successNotifiedCycleDate,
                failureMute: .untilCycleEnds,
                muteExpiresAt: nil,
                muteCycleDate: currentCycleDate,
                lastFailureNotificationAt: record.lastFailureNotificationAt
            )
        }
    }

    public static func evaluateWarningThreshold(
        record: ProfileNotificationRecord,
        currentCycleDate: String
    ) throws -> NotificationEvaluationOutcome {
        let key = "warn90-" + currentCycleDate
        if record.successNotifiedCycleDate == key {
            return .suppressed(reason: .alreadyNotifiedInCycle)
        }
        let updated = try ProfileNotificationRecord(
            successNotifiedCycleDate: key,
            failureMute: record.failureMute,
            muteExpiresAt: record.muteExpiresAt,
            muteCycleDate: record.muteCycleDate,
            lastFailureNotificationAt: record.lastFailureNotificationAt
        )
        return .deliver(updatedRecord: updated)
    }

        public static func applyMute1Hour(
        record: ProfileNotificationRecord,
        now: Date
    ) throws -> ProfileNotificationRecord {
        let expiresAt = now.addingTimeInterval(mute1HourSeconds)
        return try ProfileNotificationRecord(
            successNotifiedCycleDate: record.successNotifiedCycleDate,
            failureMute: .untilInstant,
            muteExpiresAt: expiresAt,
            muteCycleDate: nil,
            lastFailureNotificationAt: record.lastFailureNotificationAt
        )
    }
}

#if canImport(UserNotifications)
public final class DarwinNotificationDelivery: NotificationDeliverySource {
    public init() {}

    public func deliver(title: String, body: String, category: NotificationCategory) async throws {
        guard category.preference.isEnabled() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
#endif

public final class MockNotificationDelivery: NotificationDeliverySource, @unchecked Sendable {
    public struct Delivery: Equatable, Sendable {
        public let title: String
        public let body: String
        public let category: NotificationCategory
    }
    public private(set) var deliveries: [Delivery] = []

    public init() {}

    public func deliver(title: String, body: String, category: NotificationCategory) async throws {
        deliveries.append(Delivery(title: title, body: body, category: category))
    }
}
