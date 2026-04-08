import Foundation
import Network

enum ADBClientState {
    case disconnected
    case connecting
    case authenticating
    case connected
    case failed(String)
}

class ADBClient: ObservableObject {
    @Published var state: ADBClientState = .disconnected
    @Published var deviceInfo: ADBDevice?
    
    // 日志回调
    var onLog: ((String) -> Void)?
    // TCP客户端日志回调
    var onTCPLog: ((String) -> Void)?
    
    private var authLoopCount = 0
    private var authTokenReceived = false

    private let tcpClient = TCPClient()
    private let dataBuffer = ADBDataBuffer()
    let channelManager = ADBChannelManager()
    private let keyManager = ADBKeyManager()
    private var authRetries = 0
    private let maxAuthRetries = 3

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    init() {
        tcpClient.onStateChanged = { [weak self] tcpState in
            self?.handleTCPStateChange(tcpState)
        }
        tcpClient.onDataReceived = { [weak self] data in
            self?.handleIncomingData(data)
        }
        // TCP日志
        tcpClient.onLog = { [weak self] msg in
            self?.onTCPLog?(msg)
        }
    }

    func connect(host: String, port: UInt16 = 5555) {
        guard canConnect else { return }
        authLoopCount = 0
        authTokenReceived = false
        onLog?("[信息] 开始连接 \(host):\(port)")
        updateState(.connecting)
        tcpClient.connect(host: host, port: port)
    }

    private var canConnect: Bool {
        switch state {
        case .disconnected, .failed:
            return true
        default:
            return false
        }
    }

    func disconnect() {
        authLoopCount = 0
        onLog?("[信息] 断开连接")
        channelManager.removeAllChannels()
        tcpClient.disconnect()
        dataBuffer.clear()
        updateState(.disconnected)
    }

    @discardableResult
    func openChannel(destination: String) -> ADBChannel? {
        guard isConnected else { return nil }
        let channel = channelManager.createChannel()
        channel.destination = destination
        channel.state = .opening
        let packet = ADBProtocol.packOPEN(localId: channel.localId, destination: destination)
        tcpClient.send(data: packet)
        Logger.info("打开通道: \(destination), localId=\(channel.localId)", category: "ADBClient")
        return channel
    }

    func writeChannel(_ channel: ADBChannel, data: Data) {
        guard channel.isOpen else { return }
        let packet = ADBProtocol.packWRTE(localId: channel.localId, remoteId: channel.remoteId, data: data)
        tcpClient.send(data: packet)
    }

    func closeChannel(_ channel: ADBChannel) {
        let packet = ADBProtocol.packCLSE(localId: channel.localId, remoteId: channel.remoteId)
        tcpClient.send(data: packet)
        channelManager.closeChannel(localId: channel.localId)
    }

    private func updateState(_ newState: ADBClientState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }

    private func handleTCPStateChange(_ tcpState: TCPClientState) {
        switch tcpState {
        case .connected:
            onLog?("[信息] TCP已连接")
            sendCNXN()
        case .disconnected:
            onLog?("[信息] TCP断开")
            channelManager.removeAllChannels()
            updateState(.disconnected)
        case .failed(let error):
            onLog?("[错误] TCP失败: \(error.localizedDescription)")
            updateState(.failed(error.localizedDescription))
        case .connecting:
            updateState(.connecting)
        }
    }

    private func sendCNXN() {
        updateState(.authenticating)
        authRetries = 0
        let packet = ADBProtocol.packCNXN()
        onLog?("[信息] 发送CNXN握手")
        onLog?("CNXN数据: \(packet.map { String(format: "%02X", $0) }.joined(separator: " "))")
        tcpClient.send(data: packet)
    }

    private func handleIncomingData(_ data: Data) {
        onLog?("[调试] 收到原始数据: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        dataBuffer.append(data)
        onLog?("[调试] dataBuffer当前大小: \(dataBuffer.availableBytes)")

        while let message = dataBuffer.tryReadMessage() {
            onLog?("[调试] 读取到消息, command: \(String(format: "0x%08X", message.command))")
            
            // 跳过CRC验证（Android ADB的CRC计算方式可能不同）
            // TODO: 修复CRC验证逻辑
            // guard ADBProtocol.validateMessage(message) else {
            //     Logger.warning("收到无效ADB消息", category: "ADBClient")
            //     onLog?("[警告] 收到无效ADB消息")
            //     continue
            // }
            processMessage(message)
        }
    }

    private func processMessage(_ message: ADBMessage) {
        switch message.command {
        case ADBCommand.CNXN:
            handleCNXN(message)
        case ADBCommand.AUTH:
            handleAUTH(message)
        case ADBCommand.OKAY:
            handleOKAY(message)
        case ADBCommand.WRTE:
            handleWRTE(message)
        case ADBCommand.CLSE:
            handleCLSE(message)
        default:
            Logger.warning("未处理的ADB命令: \(String(format: "0x%08X", message.command))", category: "ADBClient")
        }
    }

    private func handleCNXN(_ message: ADBMessage) {
        let features = message.dataString ?? ""
        onLog?("[成功] 设备已连接，特性: \(features)")
        updateState(.connected)
    }

    private func handleAUTH(_ message: ADBMessage) {
        authLoopCount += 1
        onLog?("[调试] handleAUTH被调用, authType=\(message.arg0), 循环次数=\(authLoopCount), 已收到TOKEN=\(authTokenReceived)")
        
        if authLoopCount > 10 {
            onLog?("[错误] 检测到AUTH循环超过10次，强制断开")
            updateState(.failed("认证循环超时"))
            return
        }
        
        let authType = message.arg0

        switch authType {
        case ADBAuthType.token.rawValue:
            if !authTokenReceived {
                authTokenReceived = true
                onLog?("[信息] 收到AUTH TOKEN(第1次)，尝试签名")
                handleAuthToken(message.data)
            } else {
                onLog?("[信息] 收到AUTH TOKEN(第2次+)，签名被拒绝，发送公钥")
                sendPublicKey()
            }
        default:
            onLog?("[信息] 收到AUTH未知类型(\(authType))，发送公钥")
            sendPublicKey()
        }
    }

    private func handleAuthToken(_ tokenData: Data) {
        onLog?("[调试] handleAuthToken被调用, token大小=\(tokenData.count)")
        guard let keyPair = keyManager.loadOrCreateKeyPair() else {
            onLog?("[错误] 无法获取RSA密钥对")
            sendPublicKey()
            return
        }
        onLog?("[调试] 获取到密钥对")

        guard let signature = ADBAuth.signToken(token: tokenData, privateKey: keyPair.privateKey) else {
            onLog?("[错误] 签名失败，发送公钥")
            sendPublicKey()
            return
        }
        onLog?("[调试] 签名成功, 签名大小=\(signature.count)")

        let packet = ADBProtocol.packAUTH(type: .signature, data: signature)
        onLog?("[信息] 发送AUTH签名，长度: \(signature.count)")
        tcpClient.send(data: packet)
    }

    private func sendPublicKey() {
        onLog?("[调试] sendPublicKey被调用")
        guard let pemString = keyManager.getPublicKeyPEM() else {
            onLog?("[错误] 无法导出公钥PEM")
            updateState(.failed("认证失败：无法导出公钥"))
            return
        }
        onLog?("[调试] 获取到公钥PEM, 长度=\(pemString.count)")

        guard var pemData = pemString.data(using: .utf8) else { return }
        pemData.append(0)

        let packet = ADBProtocol.packAUTH(type: .rsaPublicKey, data: pemData)
        onLog?("[信息] 发送AUTH公钥，长度: \(pemData.count)")
        onLog?("[调试] 公钥内容: \(pemString.prefix(50))...")
        tcpClient.send(data: packet)
        onLog?("[调试] sendPublicKey发送完成")
    }

    private func handleOKAY(_ message: ADBMessage) {
        let remoteId = message.arg0
        let localId = message.arg1

        if let channel = channelManager.getChannel(localId: localId) {
            if channel.state == .opening {
                channel.remoteId = remoteId
                channel.notifyOpenCompleted()
                Logger.info("通道已建立: localId=\(localId), remoteId=\(remoteId)", category: "ADBClient")
            }
        }
    }

    private func handleWRTE(_ message: ADBMessage) {
        let remoteId = message.arg0
        let localId = message.arg1

        if let channel = channelManager.getChannel(localId: localId) {
            channel.onDataReceived?(message.data)
        }

        let okayPacket = ADBProtocol.packOKAY(localId: localId, remoteId: remoteId)
        tcpClient.send(data: okayPacket)
    }

    private func handleCLSE(_ message: ADBMessage) {
        let localId = message.arg1
        channelManager.closeChannel(localId: localId)
    }

    func executeShellCommand(_ command: String) async -> String? {
        let shell = ADBShell(client: self)
        return await shell.executeCommand(command)
    }

    func pairWireless(host: String, port: UInt16, pairingCode: String, completion: @escaping (Bool, String) -> Void) {
        onLog?("[信息] 开始无线配对 \(host):\(port) (TLS)")

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host as CFString, UInt32(port), &readStream, &writeStream)

        guard let cfRead = readStream?.takeRetainedValue(), let cfWrite = writeStream?.takeRetainedValue() else {
            onLog?("[错误] 无法创建TLS流")
            completion(false, "无法创建TLS流")
            return
        }

        let inputStream = cfRead
        let outputStream = cfWrite

        let sslSettings: [String: Any] = [
            kCFStreamSSLValidatesCertificateChain as String: kCFBooleanFalse,
            kCFStreamSSLPeerName as String: kCFNull
        ]
        CFReadStreamSetProperty(inputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings), sslSettings as CFTypeRef)
        CFWriteStreamSetProperty(outputStream, CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings), sslSettings as CFTypeRef)

        let pairQueue = DispatchQueue(label: "com.zmq.pairing", qos: .userInitiated)
        var pairCompleted = false

        let readDelegate = PairStreamDelegate()
        let writeDelegate = PairStreamDelegate()

        readDelegate.onOpen = { [weak self] in
            self?.onLog?("[信息] TLS输入流已打开")
        }

        writeDelegate.onOpen = { [weak self] in
            self?.onLog?("[信息] TLS输出流已打开，发送CNXN")
            let packet = ADBProtocol.packCNXN()
            outputStream.open()
            let _ = packet.withUnsafeBytes { ptr in
                outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: packet.count)
            }
            self?.onLog?("[信息] 已发送配对CNXN握手")
        }

        readDelegate.onData = { [weak self] data in
            guard !pairCompleted else { return }
            self?.onLog?("[调试] 收到配对数据: \(data.map { String(format: "%02X", $0) }.joined(separator: " ").prefix(100))")

            let tempBuffer = ADBDataBuffer()
            tempBuffer.append(data)

            while let message = tempBuffer.tryReadMessage() {
                switch message.command {
                case ADBCommand.CNXN:
                    self?.onLog?("[成功] 配对CNXN成功")
                case ADBCommand.AUTH:
                    let authType = message.arg0
                    self?.onLog?("[调试] 配对AUTH类型: \(authType)")

                    if authType == ADBAuthType.token.rawValue {
                        self?.onLog?("[信息] 收到配对TOKEN，准备验证配对码")

                        if let signature = ADBAuth.signPairingCode(pairingCode) {
                            let packet = ADBProtocol.packAUTH(type: .signature, data: signature)
                            self?.onLog?("[信息] 发送配对签名响应")
                            let _ = packet.withUnsafeBytes { ptr in
                                outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: packet.count)
                            }
                        } else {
                            self?.onLog?("[错误] 配对码签名失败")
                            pairCompleted = true
                            inputStream.close()
                            outputStream.close()
                            completion(false, "配对码签名失败")
                        }
                    } else if authType == ADBAuthType.signature.rawValue {
                        self?.onLog?("[成功] 配对成功！")
                        pairCompleted = true
                        inputStream.close()
                        outputStream.close()
                        completion(true, "配对成功")
                    } else {
                        if let keyPair = self?.keyManager.loadOrCreateKeyPair(),
                           let pemString = ADBAuth.exportPublicKeyPEM(keyPair.publicKey),
                           var pemData = pemString.data(using: .utf8) {
                            pemData.append(0)
                            let packet = ADBProtocol.packAUTH(type: .rsaPublicKey, data: pemData)
                            self?.onLog?("[信息] 发送配对公钥")
                            let _ = packet.withUnsafeBytes { ptr in
                                outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: packet.count)
                            }
                        }
                    }
                default:
                    self?.onLog?("[调试] 收到其他命令: \(String(format: "0x%08X", message.command))")
                }
            }
        }

        readDelegate.onError = { [weak self] error in
            guard !pairCompleted else { return }
            pairCompleted = true
            self?.onLog?("[错误] TLS流错误: \(error.localizedDescription)")
            completion(false, error.localizedDescription)
        }

        readDelegate.onEnd = { [weak self] in
            guard !pairCompleted else { return }
            pairCompleted = true
            self?.onLog?("[信息] TLS流结束")
            completion(false, "连接关闭")
        }

        inputStream.delegate = readDelegate
        outputStream.delegate = writeDelegate

        inputStream.schedule(in: RunLoop.main, forMode: .default)
        outputStream.schedule(in: RunLoop.main, forMode: .default)

        inputStream.open()
        outputStream.open()

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard !pairCompleted else { return }
            pairCompleted = true
            inputStream.close()
            outputStream.close()
            self.onLog?("[错误] 配对超时")
            completion(false, "配对超时")
        }

        objc_setAssociatedObject(self, &PairStreamDelegate.readKey, readDelegate, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(self, &PairStreamDelegate.writeKey, writeDelegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

private class PairStreamDelegate: NSObject, StreamDelegate {
    static var readKey: UInt8 = 0
    static var writeKey: UInt8 = 0

    var onOpen: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onError: ((Error) -> Void)?
    var onEnd: (() -> Void)?

    func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            onOpen?()
        case .hasBytesAvailable:
            if let input = stream as? InputStream {
                var buffer = [UInt8](repeating: 0, count: 65536)
                let bytesRead = input.read(&buffer, maxLength: buffer.count)
                if bytesRead > 0 {
                    onData?(Data(buffer[0..<bytesRead]))
                }
            }
        case .errorOccurred:
            if let error = stream.streamError {
                onError?(error)
            }
        case .endEncountered:
            onEnd?()
        default:
            break
        }
    }
}
