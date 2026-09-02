public struct CounterSnapshot: Codable, Equatable, Sendable {
    public let rx: UInt64
    public let tx: UInt64

    public init(rx: UInt64, tx: UInt64) {
        self.rx = rx
        self.tx = tx
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rx = try DecimalUInt64(from: container.superDecoder(forKey: .rx)).rawValue
        self.tx = try DecimalUInt64(from: container.superDecoder(forKey: .tx)).rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(DecimalUInt64(rawValue: rx), forKey: .rx)
        try container.encode(DecimalUInt64(rawValue: tx), forKey: .tx)
    }

    private enum CodingKeys: String, CodingKey {
        case rx
        case tx
    }
}

public struct MeasurementBaseline: Codable, Equatable, Sendable {
    public let identity: WiFiIdentitySnapshot
    public let counters: CounterSnapshot
    public let cycleID: CycleID

    public init(identity: WiFiIdentitySnapshot, counters: CounterSnapshot, cycleID: CycleID) {
        self.identity = identity
        self.counters = counters
        self.cycleID = cycleID
    }
}

public enum MeasurementStatus: String, Codable, Equatable, Sendable {
    case healthy
    case recoveryRequired
}

public struct MeasurementState: Codable, Equatable, Sendable {
    public var cycleID: CycleID
    public var usageBytes: ByteCount
    public var baseline: MeasurementBaseline?
    public var bytesSinceLastFlush: ByteCount
    public var status: MeasurementStatus

    public init(cycleID: CycleID, usageBytes: ByteCount = ByteCount(0)) {
        self.cycleID = cycleID
        self.usageBytes = usageBytes
        self.baseline = nil
        self.bytesSinceLastFlush = ByteCount(0)
        self.status = .healthy
    }
}

public struct MeasurementSample: Sendable {
    public let identity: WiFiIdentitySnapshot
    public let counters: CounterSnapshot
    public let cycleID: CycleID

    public init(identity: WiFiIdentitySnapshot, counters: CounterSnapshot, cycleID: CycleID) {
        self.identity = identity
        self.counters = counters
        self.cycleID = cycleID
    }
}

public enum PersistenceRequirement: Equatable, Sendable {
    case required
    case requiredAndImmediate
}

public enum MeasurementFailure: String, Equatable, Sendable {
    case arithmeticOverflow
}

public enum MeasurementOutcome: Equatable, Sendable {
    case baselineEstablished
    case usageAdded(delta: ByteCount, persistence: PersistenceRequirement)
    case cycleChanged
    case identityChanged
    case counterRegression
    case identityUnavailable
    case recoveryRequired(MeasurementFailure)
}

public struct MeasurementAccumulator: Sendable {
    public private(set) var state: MeasurementState

    public init(initialState: MeasurementState) {
        self.state = initialState
    }

    public mutating func ingest(_ sample: MeasurementSample) -> MeasurementOutcome {
        guard state.status == .healthy else {
            return .recoveryRequired(.arithmeticOverflow)
        }
        guard sample.identity.linkState == .associated else {
            state.baseline = nil
            return .identityUnavailable
        }
        if sample.cycleID != state.cycleID {
            state.cycleID = sample.cycleID
            state.usageBytes = ByteCount(0)
            state.bytesSinceLastFlush = ByteCount(0)
            state.baseline = MeasurementBaseline(
                identity: sample.identity,
                counters: sample.counters,
                cycleID: sample.cycleID
            )
            return .cycleChanged
        }

        guard let baseline = state.baseline else {
            state.baseline = MeasurementBaseline(
                identity: sample.identity,
                counters: sample.counters,
                cycleID: sample.cycleID
            )
            return .baselineEstablished
        }
        guard baseline.identity == sample.identity else {
            state.baseline = MeasurementBaseline(
                identity: sample.identity,
                counters: sample.counters,
                cycleID: sample.cycleID
            )
            return .identityChanged
        }
        guard sample.counters.rx >= baseline.counters.rx,
              sample.counters.tx >= baseline.counters.tx else {
            state.baseline = MeasurementBaseline(
                identity: sample.identity,
                counters: sample.counters,
                cycleID: sample.cycleID
            )
            return .counterRegression
        }

        let rxDelta = sample.counters.rx - baseline.counters.rx
        let txDelta = sample.counters.tx - baseline.counters.tx
        let deltaResult = rxDelta.addingReportingOverflow(txDelta)
        guard !deltaResult.overflow else {
            state.status = .recoveryRequired
            return .recoveryRequired(.arithmeticOverflow)
        }
        let usageResult = state.usageBytes.rawValue.addingReportingOverflow(deltaResult.partialValue)
        guard !usageResult.overflow else {
            state.status = .recoveryRequired
            return .recoveryRequired(.arithmeticOverflow)
        }
        let flushResult = state.bytesSinceLastFlush.rawValue.addingReportingOverflow(deltaResult.partialValue)
        guard !flushResult.overflow else {
            state.status = .recoveryRequired
            return .recoveryRequired(.arithmeticOverflow)
        }

        state.usageBytes = ByteCount(usageResult.partialValue)
        state.bytesSinceLastFlush = ByteCount(flushResult.partialValue)
        state.baseline = MeasurementBaseline(
            identity: sample.identity,
            counters: sample.counters,
            cycleID: sample.cycleID
        )
        let persistence: PersistenceRequirement = flushResult.partialValue >= 10_000_000
            ? .requiredAndImmediate
            : .required
        return .usageAdded(delta: ByteCount(deltaResult.partialValue), persistence: persistence)
    }

    public mutating func markDurablyFlushed() {
        guard state.status == .healthy else {
            return
        }
        state.bytesSinceLastFlush = ByteCount(0)
    }
}
