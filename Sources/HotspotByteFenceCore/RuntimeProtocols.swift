import Foundation

public protocol EnvelopeStoreProtocol: Sendable {
    func commitEnvelope(_ document: StoreEnvelopeV1, operation: JournalOperation) throws
    func loadEnvelope() throws -> StoreLoadResult<StoreEnvelopeV1>
}

public protocol InterfaceCounterSource: Sendable {
    func read(interfaceName: String) throws -> InterfaceCounters
}

public protocol WiFiIdentitySource: Sendable {
    func read(interfaceName: String) throws -> WiFiIdentityObservation
    func readAll() throws -> [WiFiIdentityObservation]
}

public protocol ClockProtocol: Sendable {
    func now() -> Date
    func monotonicNanoseconds() -> UInt64
}

public struct SystemClock: ClockProtocol, Sendable {
    public init() {}

    public func now() -> Date {
        Date()
    }

    public func monotonicNanoseconds() -> UInt64 {
        #if canImport(Darwin)
        return clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        #else
        return UInt64(DispatchTime.now().uptimeNanoseconds)
        #endif
    }
}
