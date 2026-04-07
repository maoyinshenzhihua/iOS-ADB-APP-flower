import Foundation

class ADBFileSync {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func openSyncChannel() -> ADBChannel? {
        client.openChannel(destination: "sync:\0")
    }

    func stat(path: String) async -> FileInfo? {
        guard let channel = openSyncChannel() else { return nil }

        var pathData = path.data(using: .utf8) ?? Data()
        let header = ADBProtocol.packSyncHeader(id: ADBSyncCommand.STAT, size: UInt32(pathData.count))
        client.writeChannel(channel, data: header + pathData)

        return await withCheckedContinuation { continuation in
            channel.onDataReceived = { data in
                guard data.count >= 16 else {
                    continuation.resume(returning: nil)
                    return
                }
                let id = data.readLittleEndianUInt32(at: 0)
                guard id == ADBSyncCommand.STAT else {
                    continuation.resume(returning: nil)
                    return
                }
                let mode = data.readLittleEndianUInt32(at: 4)
                let size = data.readLittleEndianUInt32(at: 8)
                let time = data.readLittleEndianUInt32(at: 12)

                let fileName = URL(fileURLWithPath: path).lastPathComponent
                let info = FileInfo(
                    name: fileName,
                    path: path,
                    mode: mode,
                    size: UInt64(size),
                    modifiedTime: Date(timeIntervalSince1970: TimeInterval(time))
                )
                continuation.resume(returning: info)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                if !channel.isClosed {
                    self.client.closeChannel(channel)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func listDirectory(path: String) async -> [FileInfo] {
        guard let channel = openSyncChannel() else { return [] }

        var pathData = path.data(using: .utf8) ?? Data()
        let header = ADBProtocol.packSyncHeader(id: ADBSyncCommand.LIST, size: UInt32(pathData.count))
        client.writeChannel(channel, data: header + pathData)

        return await withCheckedContinuation { continuation in
            var entries: [FileInfo] = []
            var buffer = Data()

            channel.onDataReceived = { data in
                buffer.append(data)

                while buffer.count >= 16 {
                    let id = buffer.readLittleEndianUInt32(at: 0)
                    if id == ADBSyncCommand.DONE {
                        self.client.closeChannel(channel)
                        continuation.resume(returning: entries)
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
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if !channel.isClosed {
                    self.client.closeChannel(channel)
                    continuation.resume(returning: entries)
                }
            }
        }
    }

    func push(localURL: URL, remotePath: String, mode: String = "0666", progress: ((Float) -> Void)? = nil) async -> Bool {
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
            progress?(Float(offset) / Float(totalSize))
        }

        let mtime = UInt32(Date().timeIntervalSince1970)
        var doneData = Data(capacity: 4)
        doneData.appendLittleEndian(mtime)
        let doneHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.DONE, size: UInt32(doneData.count))
        client.writeChannel(channel, data: doneHeader + doneData)

        return await withCheckedContinuation { continuation in
            channel.onDataReceived = { data in
                guard data.count >= 4 else {
                    continuation.resume(returning: false)
                    return
                }
                let id = data.readLittleEndianUInt32(at: 0)
                continuation.resume(returning: id == ADBSyncCommand.OKAY)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if !channel.isClosed {
                    self.client.closeChannel(channel)
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func pull(remotePath: String, localURL: URL, progress: ((Float) -> Void)? = nil) async -> Bool {
        guard let channel = openSyncChannel() else { return false }

        var pathData = remotePath.data(using: .utf8) ?? Data()
        let recvHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.RECV, size: UInt32(pathData.count))
        client.writeChannel(channel, data: recvHeader + pathData)

        return await withCheckedContinuation { continuation in
            var fileData = Data()
            var buffer = Data()
            var totalReceived: UInt64 = 0

            channel.onDataReceived = { data in
                buffer.append(data)

                while buffer.count >= 8 {
                    let id = buffer.readLittleEndianUInt32(at: 0)
                    let size = buffer.readLittleEndianUInt32(at: 4)

                    if id == ADBSyncCommand.DONE {
                        do {
                            try fileData.write(to: localURL)
                            continuation.resume(returning: true)
                        } catch {
                            Logger.error("写入文件失败: \(error)", category: "ADBFileSync")
                            continuation.resume(returning: false)
                        }
                        return
                    }

                    if id == ADBSyncCommand.FAIL {
                        continuation.resume(returning: false)
                        return
                    }

                    guard id == ADBSyncCommand.DATA else { break }

                    if buffer.count >= 8 + Int(size) {
                        fileData.append(buffer[8..<(8 + Int(size))])
                        totalReceived += UInt64(size)
                        buffer = buffer.advanced(by: 8 + Int(size))
                        progress?(Float(totalReceived) / Float(max(totalReceived, 1)))
                    } else {
                        break
                    }
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                if !channel.isClosed {
                    self.client.closeChannel(channel)
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
