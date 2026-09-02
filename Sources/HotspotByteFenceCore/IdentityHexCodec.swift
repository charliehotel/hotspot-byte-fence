import Foundation

internal enum IdentityHexCodec {
    static func parse(_ value: String, exactOctetCount: Int?) throws -> [UInt8] {
        let scalars = Array(value.unicodeScalars)
        guard scalars.count.isMultiple(of: 2), !scalars.isEmpty else {
            throw IdentityError.invalidHex
        }
        if let exactOctetCount, scalars.count != exactOctetCount * 2 {
            throw IdentityError.invalidHex
        }

        var bytes: [UInt8] = []
        for index in stride(from: 0, to: scalars.count, by: 2) {
            guard let high = digit(scalars[index]), let low = digit(scalars[index + 1]) else {
                throw IdentityError.invalidHex
            }
            bytes.append(high * 16 + low)
        }
        return bytes
    }

    static func encode(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func digit(_ scalar: UnicodeScalar) -> UInt8? {
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...70:
            return UInt8(scalar.value - 55)
        case 97...102:
            return UInt8(scalar.value - 87)
        default:
            return nil
        }
    }
}
