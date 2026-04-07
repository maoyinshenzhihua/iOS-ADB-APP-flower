import Foundation

struct ADBMessageHeader {
    let command: UInt32
    let arg0: UInt32
    let arg1: UInt32
    let dataLength: UInt32
    let dataCRC32: UInt32
    let magic: UInt32

    var isValid: Bool {
        (command ^ magic) == 0xFFFFFFFF
    }

    func encode() -> Data {
        var data = Data(capacity: ADB_HEADER_SIZE)
        data.appendLittleEndian(command)
        data.appendLittleEndian(arg0)
        data.appendLittleEndian(arg1)
        data.appendLittleEndian(dataLength)
        data.appendLittleEndian(dataCRC32)
        data.appendLittleEndian(magic)
        return data
    }

    static func decode(from data: Data) -> ADBMessageHeader? {
        guard data.count >= ADB_HEADER_SIZE else { return nil }
        let command = data.readLittleEndianUInt32(at: 0)
        let arg0 = data.readLittleEndianUInt32(at: 4)
        let arg1 = data.readLittleEndianUInt32(at: 8)
        let dataLength = data.readLittleEndianUInt32(at: 12)
        let dataCRC32 = data.readLittleEndianUInt32(at: 16)
        let magic = data.readLittleEndianUInt32(at: 20)
        let header = ADBMessageHeader(
            command: command,
            arg0: arg0,
            arg1: arg1,
            dataLength: dataLength,
            dataCRC32: dataCRC32,
            magic: magic
        )
        guard header.isValid else { return nil }
        return header
    }
}

struct ADBMessage {
    let header: ADBMessageHeader
    let data: Data

    var command: UInt32 { header.command }
    var arg0: UInt32 { header.arg0 }
    var arg1: UInt32 { header.arg1 }

    var dataString: String? {
        String(data: data, encoding: .utf8)
    }

    var totalSize: Int {
        ADB_HEADER_SIZE + Int(header.dataLength)
    }
}
