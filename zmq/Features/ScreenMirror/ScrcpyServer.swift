import Foundation

struct ScrcpyDeviceMeta {
    let width: UInt32
    let height: UInt32
    let deviceName: String
}

struct ScrcpyFrameMeta {
    let pts: UInt64
    let size: UInt32
}

enum ScrcpyControlType: UInt8 {
    case injectKeycode = 0
    case injectText = 1
    case injectTouchEvent = 2
    case injectScrollEvent = 3
    case setScreenPowerMode = 4
    case expandNotificationPanel = 5
    case expandSettingsPanel = 6
    case collapsePanels = 7
    case getClipboard = 8
    case setClipboard = 9
    case rotateDevice = 11
}

class ScrcpyServer {
    private let client: ADBClient
    private let fileSync: ADBFileSync

    var onDeviceMeta: ((ScrcpyDeviceMeta) -> Void)?
    var onVideoFrame: ((Data) -> Void)?
    var onDisconnected: (() -> Void)?

    private var videoChannel: ADBChannel?
    private var controlChannel: ADBChannel?
    private var videoBuffer = Data()
    private var deviceMeta: ScrcpyDeviceMeta?
    private var isRunning = false

    init(client: ADBClient, fileSync: ADBFileSync) {
        self.client = client
        self.fileSync = fileSync
    }

    func start(maxSize: UInt32 = 1920, maxFps: UInt32 = 30, bitRate: UInt32 = 8000000) async -> Bool {
        guard let jarURL = Bundle.main.url(forResource: "scrcpy-server", withExtension: "jar") else {
            Logger.error("找不到scrcpy-server.jar", category: "ScrcpyServer")
            return false
        }
        
        let pushSuccess = await fileSync.push(localURL: jarURL, remotePath: "/data/local/tmp/scrcpy-server.jar", mode: "0644")
        guard pushSuccess else {
            Logger.error("推送scrcpy-server失败", category: "ScrcpyServer")
            return false
        }

        let serverCommand = "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 2.7 --max-size=\(maxSize) --max-fps=\(maxFps) --bit-rate=\(bitRate) --video-codec=h264 --send-device-meta --send-frame-meta --no-audio --control --tunnel-host=127.0.0.1 --tunnel-port=27183\0"

        guard let channel = client.openChannel(destination: "shell:\(serverCommand)") else {
            Logger.error("无法打开scrcpy通道", category: "ScrcpyServer")
            return false
        }

        videoChannel = channel
        isRunning = true

        channel.onDataReceived = { [weak self] data in
            self?.handleVideoData(data)
        }

        channel.onClosed = { [weak self] in
            self?.isRunning = false
            self?.onDisconnected?()
        }

        Logger.info("scrcpy服务已启动", category: "ScrcpyServer")
        return true
    }

    func stop() {
        isRunning = false
        if let channel = videoChannel {
            client.closeChannel(channel)
            videoChannel = nil
        }
        if let channel = controlChannel {
            client.closeChannel(channel)
            controlChannel = nil
        }
        Logger.info("scrcpy服务已停止", category: "ScrcpyServer")
    }

    func sendControlEvent(type: ScrcpyControlType, data: Data) {
        guard let channel = controlChannel else { return }
        var packet = Data(capacity: 1 + data.count)
        packet.append(type.rawValue)
        packet.append(data)
        client.writeChannel(channel, data: packet)
    }

    func sendTouchEvent(action: UInt8, x: Int32, y: Int32, pointerId: Int64 = 0, pressure: UInt16 = 0xFFFF) {
        var data = Data(capacity: 29)
        data.append(action)
        var pid = pointerId.bigEndian
        data.append(Data(bytes: &pid, count: 8))
        var bx = x.bigEndian
        data.append(Data(bytes: &bx, count: 4))
        var by = y.bigEndian
        data.append(Data(bytes: &by, count: 4))
        data.append(0)
        data.append(0)
        var p = pressure.bigEndian
        data.append(Data(bytes: &p, count: 2))
        data.append(Data(repeating: 0, count: 8))
        sendControlEvent(type: .injectTouchEvent, data: data)
    }

    private func handleVideoData(_ data: Data) {
        videoBuffer.append(data)
        processVideoBuffer()
    }

    private func processVideoBuffer() {
        if deviceMeta == nil {
            guard videoBuffer.count >= 12 else { return }
            let width = videoBuffer.readBigEndianUInt32(at: 0)
            let height = videoBuffer.readBigEndianUInt32(at: 4)
            let nameLength = videoBuffer.readBigEndianUInt32(at: 8)

            guard videoBuffer.count >= 12 + Int(nameLength) else { return }
            let nameData = videoBuffer[12..<(12 + Int(nameLength))]
            let name = String(data: nameData, encoding: .utf8) ?? "Unknown"

            deviceMeta = ScrcpyDeviceMeta(width: width, height: height, deviceName: name)
            onDeviceMeta?(deviceMeta!)

            if videoBuffer.count > 12 + Int(nameLength) {
                videoBuffer = videoBuffer.advanced(by: 12 + Int(nameLength))
            } else {
                videoBuffer.removeAll()
                return
            }
        }

        while videoBuffer.count >= 12 {
            let frameSize = videoBuffer.readBigEndianUInt32(at: 8)

            guard videoBuffer.count >= 12 + Int(frameSize) else { break }

            let frameData = videoBuffer[12..<(12 + Int(frameSize))]
            onVideoFrame?(Data(frameData))

            if videoBuffer.count > 12 + Int(frameSize) {
                videoBuffer = videoBuffer.advanced(by: 12 + Int(frameSize))
            } else {
                videoBuffer.removeAll()
            }
        }
    }
}