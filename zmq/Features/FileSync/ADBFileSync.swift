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

        var pathData = path.data(using: .utf8) ?? Data()
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

        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        channel.close()
        
        Logger.info("列出目录完成，找到 \(entries.count) 个文件", category: "ADBFileSync")

        return entries
    }
}