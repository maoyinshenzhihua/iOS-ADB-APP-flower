import Foundation

class ADBFileSync {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func openSyncChannel() async -> ADBChannel? {
        Logger.info("打开sync通道...", category: "ADBFileSync")
        guard let channel = client.openChannel(destination: "sync:") else {
            Logger.error("无法创建sync通道", category: "ADBFileSync")
            return nil
        }
        
        let opened = await channel.waitForOpen()
        if opened {
            Logger.info("sync通道已打开", category: "ADBFileSync")
        } else {
            Logger.error("sync通道等待打开超时", category: "ADBFileSync")
        }
        return opened ? channel : nil
    }

    func listDirectory(path: String, timeout: TimeInterval = 15) async -> [FileInfo] {
        Logger.info("列出目录: \(path)", category: "ADBFileSync")
        
        guard let channel = await openSyncChannel() else {
            Logger.error("无法打开sync通道", category: "ADBFileSync")
            return []
        }

        var pathData = (path + "\0").data(using: .utf8) ?? Data()
        let header = ADBProtocol.packSyncHeader(id: ADBSyncCommand.LIST, size: UInt32(pathData.count))
        client.writeChannel(channel, data: header + pathData)
        Logger.info("已发送LIST命令", category: "ADBFileSync")

        var entries: [FileInfo] = []
        var buffer = Data()
        var done = false
        var receivedCount = 0

        channel.onDataReceived = { data in
            receivedCount += 1
            buffer.append(data)

            while buffer.count >= 16 && !done {
                let id = buffer.readLittleEndianUInt32(at: 0)
                
                if id == ADBSyncCommand.DONE {
                    Logger.info("收到DONE，目录列表完成，收到\(receivedCount)个数据包", category: "ADBFileSync")
                    done = true
                    return
                }

                guard id == ADBSyncCommand.DENT else { 
                    Logger.warning("收到未知SYNC命令: \(String(format: "0x%08X", id))", category: "ADBFileSync")
                    break 
                }

                let mode = buffer.readLittleEndianUInt32(at: 4)
                let size = buffer.readLittleEndianUInt32(at: 8)
                let time = buffer.readLittleEndianUInt32(at: 12)

                let nameStartIndex = 16
                var nameEndIndex: Int?

                for i in nameStartIndex..<buffer.count {
                    if buffer[i] == 0 {
                        nameEndIndex = i
                        break
                    }
                }

                guard let endIndex = nameEndIndex else {
                    break
                }

                let nameLength = endIndex - nameStartIndex
                let entrySize = 16 + nameLength + 1

                if buffer.count >= entrySize {
                    let nameStr = String(data: buffer[nameStartIndex..<endIndex], encoding: .utf8) ?? ""
                    let entry = FileInfo(
                        name: nameStr,
                        path: path.hasSuffix("/") ? "\(path)\(nameStr)" : "\(path)/\(nameStr)",
                        mode: mode,
                        size: UInt64(size),
                        modifiedTime: Date(timeIntervalSince1970: TimeInterval(time))
                    )
                    entries.append(entry)
                    buffer = buffer.advanced(by: entrySize)
                } else {
                    break
                }
            }
        }

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        channel.close()
        
        Logger.info("列出目录完成，找到 \(entries.count) 个文件", category: "ADBFileSync")

        return entries
    }

    func push(localURL: URL, remotePath: String, mode: String = "0666", progress: ((Float) -> Void)? = nil, timeout: TimeInterval = 60) async -> Bool {
        Logger.info("推送文件: \(localURL) -> \(remotePath)", category: "ADBFileSync")
        
        guard let channel = await openSyncChannel() else {
            Logger.error("无法打开sync通道", category: "ADBFileSync")
            return false
        }
        
        guard let fileData = try? Data(contentsOf: localURL) else {
            Logger.error("无法读取本地文件", category: "ADBFileSync")
            return false
        }

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

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        channel.close()
        
        Logger.info("推送文件完成", category: "ADBFileSync")
        return true
    }

    func pull(remotePath: String, localURL: URL, progress: ((Float) -> Void)? = nil, timeout: TimeInterval = 60) async -> Bool {
        Logger.info("拉取文件: \(remotePath) -> \(localURL)", category: "ADBFileSync")
        
        guard let channel = await openSyncChannel() else {
            Logger.error("无法打开sync通道", category: "ADBFileSync")
            return false
        }

        var pathData = (remotePath + "\0").data(using: .utf8) ?? Data()
        let recvHeader = ADBProtocol.packSyncHeader(id: ADBSyncCommand.RECV, size: UInt32(pathData.count))
        client.writeChannel(channel, data: recvHeader + pathData)

        var fileData = Data()
        var buffer = Data()
        var done = false

        channel.onDataReceived = { data in
            buffer.append(data)

            while buffer.count >= 8 && !done {
                let id = buffer.readLittleEndianUInt32(at: 0)
                let size = buffer.readLittleEndianUInt32(at: 4)

                if id == ADBSyncCommand.DONE {
                    done = true
                    return
                }

                if id == ADBSyncCommand.FAIL {
                    done = true
                    Logger.error("拉取文件失败", category: "ADBFileSync")
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
        }

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        channel.close()

        if fileData.isEmpty { 
            Logger.warning("拉取文件无数据", category: "ADBFileSync")
            return false 
        }
        
        do {
            try fileData.write(to: localURL)
            Logger.info("拉取文件成功", category: "ADBFileSync")
            return true
        } catch {
            Logger.error("写入文件失败: \(error)", category: "ADBFileSync")
            return false
        }
    }
}