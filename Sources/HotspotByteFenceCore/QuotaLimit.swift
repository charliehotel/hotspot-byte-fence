import Foundation

public enum QuotaLimit: Equatable, Sendable {
    case unlimited
    case finite(ByteCount)

    public var isUnlimited: Bool {
        if case .unlimited = self { return true }
        return false
    }

    public var finiteBytes: ByteCount? {
        guard case let .finite(bytes) = self else { return nil }
        return bytes
    }

    static func fromLegacyLimitBytes(_ bytes: ByteCount) -> QuotaLimit {
        bytes.rawValue >= ProfileRecord.maximumLimitBytes ? .unlimited : .finite(bytes)
    }

    var legacyLimitBytes: ByteCount {
        switch self {
        case .unlimited:
            ByteCount(ProfileRecord.maximumLimitBytes)
        case let .finite(bytes):
            bytes
        }
    }
}

extension QuotaLimit: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case bytes
    }

    private enum Kind: String, Codable {
        case unlimited
        case finite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .unlimited:
            self = .unlimited
        case .finite:
            self = .finite(try container.decode(ByteCount.self, forKey: .bytes))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unlimited:
            try container.encode(Kind.unlimited, forKey: .kind)
        case let .finite(bytes):
            try container.encode(Kind.finite, forKey: .kind)
            try container.encode(bytes, forKey: .bytes)
        }
    }
}
