import Foundation

enum ADBProtocol {

    static func packMessage(command: UInt32, arg0: UInt32, arg1: UInt32, data: Data = Data()) -> Data {
        let dataCRC32 = CRC32.compute(data: data)
        let magic = command ^ 0xFFFFFFFF
        let header = ADBMessageHeader(
            command: command,
            arg0: arg0,
            arg1: arg1,
            dataLength: UInt32(data.count),
            dataCRC32: dataCRC32,
            magic: magic
        )
        var packet = header.encode()
        packet.append(data)
        return packet
    }

    static func packMessage(command: UInt32, arg0: UInt32, arg1: UInt32, string: String) -> Data {
        guard let data = string.data(using: .utf8) else {
            return packMessage(command: command, arg0: arg0, arg1: arg1, data: Data())
        }
        return packMessage(command: command, arg0: arg0, arg1: arg1, data: data)
    }

    static func validateMessage(_ message: ADBMessage) -> Bool {
        guard message.header.isValid else { return false }
        let computedCRC = CRC32.compute(data: message.data)
        return computedCRC == message.header.dataCRC32
    }

    static func packCNXN() -> Data {
        packMessage(command: ADBCommand.CNXN, arg0: ADB_VERSION, arg1: MAX_PAYLOAD, string: ADB_FEATURES)
    }

    static func packAUTH(type: ADBAuthType, data: Data = Data()) -> Data {
        packMessage(command: ADBCommand.AUTH, arg0: type.rawValue, arg1: 0, data: data)
    }

    static func packOPEN(localId: UInt32, destination: String) -> Data {
        packMessage(command: ADBCommand.OPEN, arg0: localId, arg1: 0, string: destination + "\0")
    }

    static func packOKAY(localId: UInt32, remoteId: UInt32) -> Data {
        packMessage(command: ADBCommand.OKAY, arg0: localId, arg1: remoteId)
    }

    static func packWRTE(localId: UInt32, remoteId: UInt32, data: Data) -> Data {
        packMessage(command: ADBCommand.WRTE, arg0: localId, arg1: remoteId, data: data)
    }

    static func packCLSE(localId: UInt32, remoteId: UInt32) -> Data {
        packMessage(command: ADBCommand.CLSE, arg0: localId, arg1: remoteId)
    }

    static func packSyncHeader(id: UInt32, size: UInt32) -> Data {
        var data = Data(capacity: 8)
        data.appendLittleEndian(id)
        data.appendLittleEndian(size)
        return data
    }
}
