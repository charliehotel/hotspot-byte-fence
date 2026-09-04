import Foundation

public struct WiFiObservationV1: Equatable, Sendable {
    public let interfaceName: String
    public let linkState: WiFiLinkState
    public let ssidBytes: [UInt8]?
    public let bssid: String?
    public let source: PreferenceObservationSourceV1
    public let processLifecycleID: UUID
    public let monotonicTimestampNanoseconds: UInt64

    public init(
        interfaceName: String,
        linkState: WiFiLinkState,
        ssidBytes: [UInt8]?,
        bssid: String?,
        source: PreferenceObservationSourceV1,
        processLifecycleID: UUID,
        monotonicTimestampNanoseconds: UInt64
    ) throws {
        let trimmedName = interfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName == interfaceName else {
            throw ProfileRecordValidationError.invalidIdentity
        }
        guard source != .none else {
            throw ProfileRecordValidationError.invalidObservation
        }
        if let bssid {
            _ = try BSSID(string: bssid)
        }
        self.interfaceName = interfaceName
        self.linkState = linkState
        self.ssidBytes = ssidBytes
        self.bssid = bssid
        self.source = source
        self.processLifecycleID = processLifecycleID
        self.monotonicTimestampNanoseconds = monotonicTimestampNanoseconds
    }
}

public struct WiFiObservationWindowTracker: Sendable {
    public static let requiredAwakeDurationNanoseconds: UInt64 = 30_000_000_000
    public static let maximumAllowedGapNanoseconds: UInt64 = 2_000_000_000

    public let processLifecycleID: UUID
    public let targetInterfaceName: String
    public let targetSSIDBytes: [UInt8]
    public let targetBSSID: String?
    public private(set) var windowStartNanoseconds: UInt64
    public private(set) var lastObservationNanoseconds: UInt64
    public private(set) var totalAwakeDurationNanoseconds: UInt64
    public private(set) var maxGapNanoseconds: UInt64
    public private(set) var hasEventBackedObservation: Bool
    public private(set) var hasPollBackedObservation: Bool
    public private(set) var targetAbsentAtEnd: Bool
    public private(set) var unclassifiedReconnectDetected: Bool
    public private(set) var isInterrupted: Bool

    public init(
        processLifecycleID: UUID,
        targetInterfaceName: String,
        targetSSIDBytes: [UInt8],
        targetBSSID: String?,
        startNanoseconds: UInt64
    ) {
        self.processLifecycleID = processLifecycleID
        self.targetInterfaceName = targetInterfaceName
        self.targetSSIDBytes = targetSSIDBytes
        self.targetBSSID = targetBSSID
        self.windowStartNanoseconds = startNanoseconds
        self.lastObservationNanoseconds = startNanoseconds
        self.totalAwakeDurationNanoseconds = 0
        self.maxGapNanoseconds = 0
        self.hasEventBackedObservation = false
        self.hasPollBackedObservation = false
        self.targetAbsentAtEnd = false
        self.unclassifiedReconnectDetected = false
        self.isInterrupted = false
    }

    public mutating func recordObservation(
        _ observation: WiFiObservationV1,
        isManualReconnectTokenValid: Bool
    ) {
        guard !isInterrupted else {
            return
        }
        guard observation.processLifecycleID == processLifecycleID else {
            isInterrupted = true
            return
        }

        if observation.monotonicTimestampNanoseconds >= lastObservationNanoseconds {
            let gap = observation.monotonicTimestampNanoseconds - lastObservationNanoseconds
            if gap > maxGapNanoseconds {
                maxGapNanoseconds = gap
            }
            totalAwakeDurationNanoseconds += gap
            lastObservationNanoseconds = observation.monotonicTimestampNanoseconds
        }

        switch observation.source {
        case .eventBacked:
            hasEventBackedObservation = true
        case .pollBacked:
            hasPollBackedObservation = true
        case .none, .lifecycleOnly:
            break
        }

        let isTargetMatch = observation.interfaceName == targetInterfaceName &&
            observation.ssidBytes == targetSSIDBytes

        if isTargetMatch && observation.linkState == .associated {
            if !isManualReconnectTokenValid {
                unclassifiedReconnectDetected = true
            }
            targetAbsentAtEnd = false
        } else {
            targetAbsentAtEnd = true
        }
    }

    public mutating func interrupt() {
        isInterrupted = true
    }

    public func summarizeSuppression() throws -> ObservationSummaryRecord {
        let awakeSeconds = UInt(totalAwakeDurationNanoseconds / 1_000_000_000)
        let maxGapSeconds = UInt((maxGapNanoseconds + 999_999_999) / 1_000_000_000)
        let canVerify = !isInterrupted &&
            totalAwakeDurationNanoseconds >= Self.requiredAwakeDurationNanoseconds &&
            maxGapNanoseconds <= Self.maximumAllowedGapNanoseconds &&
            hasEventBackedObservation &&
            targetAbsentAtEnd &&
            !unclassifiedReconnectDetected

        if canVerify {
            return try ObservationSummaryRecord(
                result: .verified,
                source: .eventBacked,
                awakeSecondsObserved: awakeSeconds,
                maxGapSeconds: maxGapSeconds,
                targetAbsentAtEnd: true
            )
        } else {
            let effectiveSource: PreferenceObservationSourceV1 = if hasEventBackedObservation {
                .eventBacked
            } else if hasPollBackedObservation {
                .pollBacked
            } else {
                .lifecycleOnly
            }
            return try ObservationSummaryRecord(
                result: .unverified,
                source: effectiveSource,
                awakeSecondsObserved: awakeSeconds,
                maxGapSeconds: maxGapSeconds,
                targetAbsentAtEnd: targetAbsentAtEnd
            )
        }
    }

    public func summarizeRestoration() throws -> ObservationSummaryRecord {
        let awakeSeconds = UInt(totalAwakeDurationNanoseconds / 1_000_000_000)
        let maxGapSeconds = UInt((maxGapNanoseconds + 999_999_999) / 1_000_000_000)
        let canVerify = !isInterrupted &&
            totalAwakeDurationNanoseconds >= Self.requiredAwakeDurationNanoseconds &&
            maxGapNanoseconds <= Self.maximumAllowedGapNanoseconds &&
            hasEventBackedObservation &&
            targetAbsentAtEnd

        let effectiveSource: PreferenceObservationSourceV1 = if hasEventBackedObservation {
            .eventBacked
        } else if hasPollBackedObservation {
            .pollBacked
        } else {
            .lifecycleOnly
        }

        return try ObservationSummaryRecord(
            result: canVerify ? .verified : .unverified,
            source: effectiveSource,
            awakeSecondsObserved: awakeSeconds,
            maxGapSeconds: maxGapSeconds,
            targetAbsentAtEnd: targetAbsentAtEnd
        )
    }
}
