import Foundation

class ADBFileSync {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func openSyncChannel() -> ADBChannel? {
        client.openChannel(destination: "sync:\0")
    }

    func stat(path: String, timeout: TimeInterval = 10) -> FileInfo? {
        guard let channel = openSyncChannel() else { return nil }

        var pathData = path.data(using: .utf8) ?? Data()
        let header = ADBProtocol.packSyncHeader(id: ADBSyncCommand.STAT, size: UInt32(pathData.count))
        client.writeChannel(channel, data: header + pathData)

        var result: FileInfo?
        var buffer = Data()
        let lock = NSLock()

        channel.onDataReceived = { data in
            lock.lock()
            buffer.append(data)

            if buffer.count >= 16 {
                let id = buffer.readLittleEndianUInt32(at: 0)
                guard id == ADBSyncCommand.STAT else {
                    lock.unlock()
                    return
                }
                let mode = buffer.readLittleEndianUInt32(at: 4)
                let size = buffer.readLittleEndianUInt32(at: 8)
                let time = buffer.readLittleEndianUInt32(at: 12)

                let fileName = URL(fileURLWithPath: path).lastPathComponent
                result = FileInfo(
                    name: fileName,
                    path: path,
                    mode: mode,
                    size: UInt64(size),
                    modifiedTime: Date(timeIntervalSince1970: TimeInterval(time))
                )
            }
            lock.unlock()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if !channel.isClosed {
                self.client.closeChannel(channel)
            }
        }

        return result
    }

    func listDirectory(path: String, timeout: TimeInterval = 15) -> [FileInfo] {
        guard let channel = openSyncChannel() else { return [] }

        var pathData = path.data(using: .utf8) ?? Data()
        let header = ADBProtocol.packSyncHeader(id: ADBSyncCommand.LIST, size: UInt32(pathData.count))
        client.writeChannel(channel, data: header + pathData)

        var entries: [FileInfo] = []
        var buffer = Data()
        let lock = NSLock()
        var done = false

        channel.onDataReceived = { data in
            lock.lock()
            buffer.append(data)

            while buffer.count >= 16 && !done {
                let id = buffer.readLittleEndianUInt32(at: 0)
                if id == ADBSyncCommand.DONE {
                    done = true
                    lock.unlock()
                    return
                }

                guard id == ADBSyncCommand.DENT else { break }

                let mode = buffer.readLittleEndianUInt32(at: 4)
                let size = buffer.readLittleEndianUInt32(at: 8)
                let time = buffer.readLittleEndianUInt32(at: 12)

                if buffer.count >= 17 {
                    let nameData = buffer[16...]
                    if let nullIndex = nameData.firstIndex(of: 0) {
                        let nameLength = nullIndex - 16 + 1
                        if buffer.count >= 16 + nameLength {
                            let nameStr = String(data: buffer[16..<(16 + nameLength - 1)], encoding: .utf8) ?? ""
                            let entry = FileInfo(
                                name: nameStr,
                                path: path.hasSuffix("/") ? "\(path)\(nameStr)" : "\(path)/\(nameStr)",
                                mode: mode,
                                size: UInt64(size),
                                modifiedTime: Date(timeIntervalSince1970: TimeInterval(time))
                            )
                            entries.append(entry)
                            buffer = buffer.advanced(by: 16 + nameLength)
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            lock.unlock()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if !channel.isClosed {
                self.client.closeChannel(channel)
            }
        }

        return entries
    }

    func push(localURL: URL, remotePath: String, mode: String = "0666", timeout: TimeInterval = 60) -> Bool {
        guard let channel = openSyncChannel() else { return false }
        guard let fileData = try? Data(contentsOf: localURL) else { return false }

        let sendPath = "\(remotePath),\(mode)\0"
        guard let sendPathData = sendPath.data(using: .utf8) else { return false }

        let sendHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.SEND, size: UInt32(sendPathData.count))
        client.writeChannel(channel, data: sendHeader + sendPathData)

        var offset = 0
        let totalSize = fileData.count
        let blockSize = Int(ADB_SYNC_MAX_BLOCK_SIZE)

        while offset < totalSize {
            let end = min(offset + blockSize, totalSize)
            let chunk = fileData[offset..<end]
            let dataHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.DATA, size: UInt32(chunk.count))
            client.writeChannel(channel, data: dataHeader + Data(chunk))
            offset = end
        }

        let mtime = UInt32(Date().timeIntervalSince1970)
        var doneData = Data(capacity: 4)
        doneData.appendLittleEndian(mtime)
        let doneHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.DONE, size: UInt32(doneData.count))
        client.writeChannel(channel, data: doneHeader + doneData)

        var result = false
        let lock = NSLock()

        channel.onDataReceived = { data in
            guard data.count >= 4 else { return }
            let id = data.readLittleEndianUInt32(at: 0)
            lock.lock()
            result = (id == ADBSyncCommand.OKAY)
            lock.unlock()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if !channel.isClosed {
                self.client.closeChannel(channel)
            }
        }

        return result
    }

    func pull(remotePath: String, localURL: URL, timeout: TimeInterval = 60) -> Bool {
        guard let channel = openSyncChannel() else { return false }

        var pathData = remotePath.data(using: .utf8) ?? Data()
        let recvHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.RECV, size: UInt32(pathData.count))
        client.writeChannel(channel, data: recvHeader + pathData)

        var fileData = Data()
        var buffer = Data()
        var done = false
        let lock = NSLock()

        channel.onDataReceived = { data in
            lock.lock()
            buffer.append(data)

            while buffer.count >= 8 && !done {
                let id = buffer.readLittleEndianUInt32(at: 0)
                let size = buffer.readLittleEndianUInt32(at: 4)

                if id == ADBSyncCommand.DONE {
                    done = true
                    lock.unlock()
                    return
                }

                if id == ADBSyncCommand.FAIL {
                    done = true
                    lock.unlock()
                    return
                }

                guard id == ADBSyncCommand.DATA else { break }

                if buffer.count >= 8 + Int(size) {
                    fileData.append(buffer[8..<(8 + Int(size))])
                    buffer = buffer.advanced(by: 8 + Int(size))
                } else {
                    break
                }
            }
            lock.unlock()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if !channel.isClosed {
                self.client.closeChannel(channel)
            }
        }

        if fileData.isEmpty { return false }
        do {
            try fileData.write(to: localURL)
            return true
        } catch {
            Logger.error("写入文件失败: \(error)", category: "ADBFileSync")
            return false
        }
    }
}
