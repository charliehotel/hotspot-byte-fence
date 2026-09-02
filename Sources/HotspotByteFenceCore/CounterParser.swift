public struct CounterRecordLayout: Sendable, Equatable {
    public let headerSize: Int
    public let minimumRecordSize: Int
    public let messageLengthOffset: Int
    public let messageTypeOffset: Int
    public let interfaceIndexOffset: Int
    public let dataOffset: Int
    public let dataSize: Int
    public let rxOffset: Int
    public let txOffset: Int

    public init(
        headerSize: Int,
        minimumRecordSize: Int? = nil,
        messageLengthOffset: Int,
        messageTypeOffset: Int,
        interfaceIndexOffset: Int,
        dataOffset: Int,
        dataSize: Int,
        rxOffset: Int,
        txOffset: Int
    ) {
        self.headerSize = headerSize
        self.minimumRecordSize = minimumRecordSize ?? headerSize
        self.messageLengthOffset = messageLengthOffset
        self.messageTypeOffset = messageTypeOffset
        self.interfaceIndexOffset = interfaceIndexOffset
        self.dataOffset = dataOffset
        self.dataSize = dataSize
        self.rxOffset = rxOffset
        self.txOffset = txOffset
    }
}

public struct CounterParserConfiguration: Sendable, Equatable {
    public let layout: CounterRecordLayout
    public let targetInterfaceIndex: UInt32
    public let targetInterfaceName: String
    public let targetRecordType: UInt8

    public init(
        layout: CounterRecordLayout,
        targetInterfaceIndex: UInt32,
        targetInterfaceName: String,
        targetRecordType: UInt8
    ) {
        self.layout = layout
        self.targetInterfaceIndex = targetInterfaceIndex
        self.targetInterfaceName = targetInterfaceName
        self.targetRecordType = targetRecordType
    }
}

public protocol InterfaceNameResolving: Sendable {
    func name(for interfaceIndex: UInt32) -> String?
}

public struct InterfaceCounters: Equatable, Sendable {
    public let rx: UInt64
    public let tx: UInt64
    public let total: UInt64

    public init(rx: UInt64, tx: UInt64, total: UInt64) {
        self.rx = rx
        self.tx = tx
        self.total = total
    }
}

public enum CounterParseError: Error, Equatable, Sendable {
    case bufferTruncated
    case invalidMessageLength
    case dataOutOfBounds
    case targetMissing
    case duplicateTarget
    case interfaceNameUnavailable
    case interfaceMismatch
    case counterOverflow
}

public struct CounterParser: Sendable {
    public let configuration: CounterParserConfiguration

    public init(configuration: CounterParserConfiguration) {
        self.configuration = configuration
    }

    public func parse(
        _ buffer: [UInt8],
        interfaceNames: any InterfaceNameResolving
    ) throws -> InterfaceCounters {
        var offset = 0
        var target: InterfaceCounters?
        while offset < buffer.count {
            let remaining = buffer.count - offset
            guard configuration.layout.minimumRecordSize > 0,
                  configuration.layout.minimumRecordSize <= configuration.layout.headerSize,
                  remaining >= configuration.layout.minimumRecordSize else {
                throw CounterParseError.bufferTruncated
            }
            let headerEnd = try checkedAdd(offset, configuration.layout.minimumRecordSize)
            let messageLength = try readUInt16(
                buffer,
                at: try checkedAdd(offset, configuration.layout.messageLengthOffset),
                upperBound: headerEnd
            )
            let recordLength = Int(messageLength)
            guard recordLength >= configuration.layout.minimumRecordSize, recordLength <= remaining else {
                throw CounterParseError.invalidMessageLength
            }
            let recordEnd = try checkedAdd(offset, recordLength)
            let messageType = try readByte(
                buffer,
                at: try checkedAdd(offset, configuration.layout.messageTypeOffset),
                upperBound: recordEnd
            )

            if messageType == configuration.targetRecordType {
                guard recordLength >= configuration.layout.headerSize else {
                    throw CounterParseError.invalidMessageLength
                }
                let interfaceIndex = try readUInt32(
                    buffer,
                    at: try checkedAdd(offset, configuration.layout.interfaceIndexOffset),
                    upperBound: recordEnd
                )
                let dataStart = try checkedAdd(offset, configuration.layout.dataOffset)
                let dataEnd = try checkedAdd(dataStart, configuration.layout.dataSize)
                guard dataStart >= offset,
                      dataEnd <= recordEnd,
                      dataEnd <= buffer.count,
                      configuration.layout.dataSize > 0 else {
                    throw CounterParseError.dataOutOfBounds
                }
                let rxPosition = try checkedAdd(dataStart, configuration.layout.rxOffset)
                let txPosition = try checkedAdd(dataStart, configuration.layout.txOffset)
                guard try rangeFits(start: rxPosition, length: 8, lowerBound: dataStart, upperBound: dataEnd),
                      try rangeFits(start: txPosition, length: 8, lowerBound: dataStart, upperBound: dataEnd) else {
                    throw CounterParseError.dataOutOfBounds
                }
                let resolvedName = interfaceNames.name(for: interfaceIndex)
                if interfaceIndex == configuration.targetInterfaceIndex {
                    guard let resolvedName else {
                        throw CounterParseError.interfaceNameUnavailable
                    }
                    guard resolvedName == configuration.targetInterfaceName else {
                        throw CounterParseError.interfaceMismatch
                    }
                } else if resolvedName == configuration.targetInterfaceName {
                    throw CounterParseError.interfaceMismatch
                } else {
                    offset = recordEnd
                    continue
                }

                guard target == nil else {
                    throw CounterParseError.duplicateTarget
                }
                let rx = try readUInt64(buffer, at: rxPosition, upperBound: dataEnd)
                let tx = try readUInt64(buffer, at: txPosition, upperBound: dataEnd)
                let totalResult = rx.addingReportingOverflow(tx)
                guard !totalResult.overflow else {
                    throw CounterParseError.counterOverflow
                }
                target = InterfaceCounters(rx: rx, tx: tx, total: totalResult.partialValue)
            }
            offset = recordEnd
        }

        guard let target else {
            throw CounterParseError.targetMissing
        }
        return target
    }

    private func checkedAdd(_ first: Int, _ second: Int) throws -> Int {
        guard second >= 0 else {
            throw CounterParseError.dataOutOfBounds
        }
        let result = first.addingReportingOverflow(second)
        guard !result.overflow else {
            throw CounterParseError.dataOutOfBounds
        }
        return result.partialValue
    }

    private func rangeFits(
        start: Int,
        length: Int,
        lowerBound: Int,
        upperBound: Int
    ) throws -> Bool {
        guard start >= lowerBound, length >= 0 else {
            return false
        }
        let end = try checkedAdd(start, length)
        return end <= upperBound
    }

    private func readByte(_ buffer: [UInt8], at position: Int, upperBound: Int) throws -> UInt8 {
        guard position >= 0, position < upperBound, position < buffer.count else {
            throw CounterParseError.bufferTruncated
        }
        return buffer[position]
    }

    private func readUInt16(_ buffer: [UInt8], at position: Int, upperBound: Int) throws -> UInt16 {
        let first = try readByte(buffer, at: position, upperBound: upperBound)
        let second = try readByte(buffer, at: try checkedAdd(position, 1), upperBound: upperBound)
        return UInt16(first) | UInt16(second) << 8
    }

    private func readUInt32(_ buffer: [UInt8], at position: Int, upperBound: Int) throws -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 {
            let byte = try readByte(buffer, at: try checkedAdd(position, index), upperBound: upperBound)
            value |= UInt32(byte) << UInt32(index * 8)
        }
        return value
    }

    private func readUInt64(_ buffer: [UInt8], at position: Int, upperBound: Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            let byte = try readByte(buffer, at: try checkedAdd(position, index), upperBound: upperBound)
            value |= UInt64(byte) << UInt64(index * 8)
        }
        return value
    }
}
