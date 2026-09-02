import Foundation

func encodeExplicitOptional<Value: Encodable, Key: CodingKey>(
    _ value: Value?,
    in container: inout KeyedEncodingContainer<Key>,
    forKey key: Key
) throws {
    if let value {
        try container.encode(value, forKey: key)
    } else {
        try container.encodeNil(forKey: key)
    }
}
