import Foundation

public enum NumericError: Error, Equatable {
    case overflow
    case invalidUnsignedDecimal
}

public struct DecimalUInt64: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(decimalString: String) throws {
        self.rawValue = try UnsignedDecimal.parse(decimalString, requireCanonical: true)
    }

    public var decimalString: String {
        String(rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(decimalString: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(decimalString)
    }
}

public struct ByteCount: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public func adding(_ other: ByteCount) throws -> ByteCount {
        let result = rawValue.addingReportingOverflow(other.rawValue)
        guard !result.overflow else {
            throw NumericError.overflow
        }
        return ByteCount(result.partialValue)
    }

    public func subtracting(_ other: ByteCount) throws -> ByteCount {
        let result = rawValue.subtractingReportingOverflow(other.rawValue)
        guard !result.overflow else {
            throw NumericError.overflow
        }
        return ByteCount(result.partialValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try UnsignedDecimal.parse(container.decode(String.self), requireCanonical: true)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(rawValue))
    }
}

public struct DataLimit: Codable, Equatable, Hashable, Sendable {
    public static let minimumHundredthsGB: UInt64 = 1
    public static let maximumHundredthsGB: UInt64 = 100_000
    public static let bytesPerHundredthGB: UInt64 = 10_000_000

    public let hundredthsGB: UInt64

    public init(hundredthsGB: UInt64) throws {
        guard Self.minimumHundredthsGB...Self.maximumHundredthsGB ~= hundredthsGB else {
            throw NumericError.invalidUnsignedDecimal
        }
        self.hundredthsGB = hundredthsGB
    }

    public init(from decoder: Decoder) throws {
        let value = try DecimalUInt64(from: decoder)
        try self.init(hundredthsGB: value.rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        try DecimalUInt64(rawValue: hundredthsGB).encode(to: encoder)
    }

    public var bytes: ByteCount {
        ByteCount(hundredthsGB * Self.bytesPerHundredthGB)
    }
}

public enum DataLimitParser {
    public static func parse(_ input: String, decimalSeparator: Character) throws -> DataLimit {
        let parts = input.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts.isEmpty else {
            throw NumericError.invalidUnsignedDecimal
        }

        let whole = try UnsignedDecimal.parse(String(parts[0]), requireCanonical: false)
        let fraction: UInt64
        if parts.count == 1 {
            fraction = 0
        } else {
            let fractionalPart = String(parts[1])
            guard !fractionalPart.isEmpty, fractionalPart.count <= 2 else {
                throw NumericError.invalidUnsignedDecimal
            }
            let parsedFraction = try UnsignedDecimal.parse(fractionalPart, requireCanonical: false)
            fraction = fractionalPart.count == 1 ? parsedFraction * 10 : parsedFraction
        }

        let scaledWhole = whole.multipliedReportingOverflow(by: 100)
        guard !scaledWhole.overflow else {
            throw NumericError.overflow
        }
        let combined = scaledWhole.partialValue.addingReportingOverflow(fraction)
        guard !combined.overflow else {
            throw NumericError.overflow
        }
        return try DataLimit(hundredthsGB: combined.partialValue)
    }

    public static func parse(_ input: String) throws -> DataLimit {
        try parse(input, decimalSeparator: ".")
    }
}

public enum UsageFormatter {
    public static func format(_ bytes: ByteCount) throws -> String {
        let scaled = bytes.rawValue / DataLimit.bytesPerHundredthGB
        let remainder = bytes.rawValue % DataLimit.bytesPerHundredthGB
        let rounded = scaled.addingReportingOverflow(remainder >= 5_000_000 ? 1 : 0)
        guard !rounded.overflow else {
            throw NumericError.overflow
        }
        let whole = rounded.partialValue / 100
        let fractional = rounded.partialValue % 100
        let fractionalText = fractional < 10 ? "0\(fractional)" : String(fractional)
        return "\(whole).\(fractionalText)GB"
    }

    public static func formatGB(_ bytes: ByteCount) -> String {
        (try? format(bytes)) ?? "0.00GB"
    }
}

public enum UsageBand: String, Codable, Equatable, Sendable {
    case normal
    case notice
    case warning
    case critical
    case limitReached

    public static func forUsage(_ usage: ByteCount, limit: DataLimit) -> UsageBand {
        let limitBytes = limit.bytes.rawValue
        if usage.rawValue >= limitBytes {
            return .limitReached
        }
        if usage.rawValue >= limitBytes / 100 * 90 {
            return .critical
        }
        if usage.rawValue >= limitBytes / 100 * 80 {
            return .warning
        }
        if usage.rawValue >= limitBytes / 100 * 50 {
            return .notice
        }
        return .normal
    }
}

private enum UnsignedDecimal {
    static func parse(_ value: String, requireCanonical: Bool) throws -> UInt64 {
        guard !value.isEmpty else {
            throw NumericError.invalidUnsignedDecimal
        }
        if requireCanonical, value.count > 1, value.first == "0" {
            throw NumericError.invalidUnsignedDecimal
        }

        var result: UInt64 = 0
        for scalar in value.unicodeScalars {
            guard (48...57).contains(scalar.value) else {
                throw NumericError.invalidUnsignedDecimal
            }
            let multiplied = result.multipliedReportingOverflow(by: 10)
            guard !multiplied.overflow else {
                throw NumericError.overflow
            }
            let added = multiplied.partialValue.addingReportingOverflow(UInt64(scalar.value - 48))
            guard !added.overflow else {
                throw NumericError.overflow
            }
            result = added.partialValue
        }
        return result
    }
}
