import Foundation

class ADBDataBuffer {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
    }

    func tryReadMessage() -> ADBMessage? {
        lock.lock()
        defer { lock.unlock() }

        guard buffer.count >= ADB_HEADER_SIZE else { return nil }

        guard let header = ADBMessageHeader.decode(from: buffer) else {
            buffer.removeAll()
            return nil
        }

        let totalSize = ADB_HEADER_SIZE + Int(header.dataLength)
        guard buffer.count >= totalSize else { return nil }

        let messageData = buffer[ADB_HEADER_SIZE..<totalSize]
        let message = ADBMessage(header: header, data: Data(messageData))

        if buffer.count > totalSize {
            buffer = buffer.advanced(by: totalSize)
        } else {
            buffer.removeAll()
        }

        return message
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    var availableBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
}
