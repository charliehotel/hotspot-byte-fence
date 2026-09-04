#if canImport(Darwin)
import Darwin

public enum DarwinCounterLayout {
    public static func netRTInterfaceList2() throws -> CounterRecordLayout {
        guard let messageLengthOffset = MemoryLayout<if_msghdr2>.offset(of: \if_msghdr2.ifm_msglen),
              let messageTypeOffset = MemoryLayout<if_msghdr2>.offset(of: \if_msghdr2.ifm_type),
              let interfaceIndexOffset = MemoryLayout<if_msghdr2>.offset(of: \if_msghdr2.ifm_index),
              let dataOffset = MemoryLayout<if_msghdr2>.offset(of: \if_msghdr2.ifm_data),
              let rxOffset = MemoryLayout<if_data64>.offset(of: \if_data64.ifi_ibytes),
              let txOffset = MemoryLayout<if_data64>.offset(of: \if_data64.ifi_obytes) else {
            throw DarwinCounterSourceError.unsupportedLayout
        }
        return CounterRecordLayout(
            headerSize: MemoryLayout<if_msghdr2>.size,
            minimumRecordSize: max(messageLengthOffset + 2, messageTypeOffset + 1),
            messageLengthOffset: messageLengthOffset,
            messageTypeOffset: messageTypeOffset,
            interfaceIndexOffset: interfaceIndexOffset,
            dataOffset: dataOffset,
            dataSize: MemoryLayout<if_data64>.size,
            rxOffset: rxOffset,
            txOffset: txOffset
        )
    }
}

public enum DarwinCounterSourceError: Error, Equatable, Sendable {
    case interfaceUnavailable
    case unsupportedLayout
    case sysctlFailed(Int32)
    case invalidBufferLength
}

public struct DarwinInterfaceCounterSource: InterfaceCounterSource {
    public init() {}

    public func read(interfaceName: String) throws -> InterfaceCounters {
        let interfaceIndex = interfaceName.withCString { if_nametoindex($0) }
        guard interfaceIndex != 0 else {
            throw DarwinCounterSourceError.interfaceUnavailable
        }
        let layout = try DarwinCounterLayout.netRTInterfaceList2()
        let buffer = try readInterfaceList()
        let parser = CounterParser(configuration: CounterParserConfiguration(
            layout: layout,
            targetInterfaceIndex: interfaceIndex,
            targetInterfaceName: interfaceName,
            targetRecordType: UInt8(RTM_IFINFO2)
        ))
        return try parser.parse(buffer, interfaceNames: SystemInterfaceNameResolver())
    }

    private func readInterfaceList() throws -> [UInt8] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else {
            throw DarwinCounterSourceError.sysctlFailed(errno)
        }
        guard length > 0 else {
            throw DarwinCounterSourceError.invalidBufferLength
        }
        var buffer = [UInt8](repeating: 0, count: length)
        let result = buffer.withUnsafeMutableBytes { rawBuffer in
            sysctl(&mib, UInt32(mib.count), rawBuffer.baseAddress, &length, nil, 0)
        }
        guard result == 0 else {
            throw DarwinCounterSourceError.sysctlFailed(errno)
        }
        guard length > 0, length <= buffer.count else {
            throw DarwinCounterSourceError.invalidBufferLength
        }
        return Array(buffer.prefix(length))
    }
}

private struct SystemInterfaceNameResolver: InterfaceNameResolving {
    func name(for interfaceIndex: UInt32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        guard let baseAddress = buffer.withUnsafeMutableBufferPointer({ pointer in
            if_indextoname(interfaceIndex, pointer.baseAddress)
        }) else {
            return nil
        }
        return String(cString: baseAddress)
    }
}
#endif
