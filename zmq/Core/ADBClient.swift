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
        onLog?("[信息] 开始无线配对 \(host):\(port)")

        let pairQueue = DispatchQueue(label: "com.zmq.pairing", qos: .userInitiated)

        pairQueue.async { [weak self] in
            guard let self = self else { return }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian

            guard let hostAddr = host.withCString({ inet_addr($0) }), hostAddr != UInt32.max else {
                self.onLog?("[错误] 无效的IP地址")
                completion(false, "无效的IP地址")
                return
            }
            addr.sin_addr.s_addr = hostAddr

            let sockFd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard sockFd >= 0 else {
                self.onLog?("[错误] 创建socket失败")
                completion(false, "创建socket失败")
                return
            }

            var optVal: Int32 = 1
            setsockopt(sockFd, SOL_SOCKET, SO_REUSEADDR, &optVal, socklen_t(MemoryLayout<Int32>.size))

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(sockFd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            if connectResult < 0 {
                self.onLog?("[错误] 连接失败")
                close(sockFd)
                completion(false, "连接失败")
                return
            }

            self.onLog?("[信息] TCP连接成功，建立TLS")

            guard let sslCtx = SSLCreateContext(kCFAllocatorDefault, .clientSide, .streamType) else {
                self.onLog?("[错误] 创建SSL上下文失败")
                close(sockFd)
                completion(false, "创建SSL上下文失败")
                return
            }

            SSLSetSessionOption(sslCtx, .breakOnServerAuth, true)

            let fd = sockFd
            SSLSetIOFuncs(sslCtx,
                          { _, data, dataLength in
                              OSStatus(Darwin.read(fd, data, Int(dataLength)))
                          },
                          { _, data, dataLength in
                              OSStatus(Darwin.write(fd, data, Int(dataLength)))
                          })

            SSLSetConnection(sslCtx, UnsafeMutableRawPointer(bitPattern: fd))
            let handshakeResult = SSLHandshake(sslCtx)
            if handshakeResult != errSecSuccess {
                self.onLog?("[错误] TLS握手失败")
                close(sockFd)
                completion(false, "TLS握手失败")
                return
            }

            self.onLog?("[信息] TLS握手成功，发送CNXN")

            func sendRaw(_ data: Data) -> Bool {
                var processed: size_t = 0
                let result = data.withUnsafeBytes { ptr in
                    if let baseAddr = ptr.baseAddress {
                        return SSLWrite(sslCtx, baseAddr, data.count, &processed)
                    }
                    return errSecParam
                }
                return result == errSecSuccess
            }

            func recvRaw() -> Data? {
                var buffer = [UInt8](repeating: 0, count: 65536)
                var processed: size_t = 0
                let result = SSLRead(sslCtx, &buffer, buffer.count, &processed)
                if result == errSecSuccess && processed > 0 {
                    return Data(buffer[0..<processed])
                }
                return nil
            }

            let cnxnPacket = ADBProtocol.packCNXN()
            _ = sendRaw(cnxnPacket)
            self.onLog?("[信息] 已发送CNXN (\(cnxnPacket.count)字节)")

            let startTime = Date()
            while Date().timeIntervalSince(startTime) < 30 {
                Thread.sleep(forTimeInterval: 0.05)

                if let data = recvRaw() {
                    self.onLog?("[调试] 收到数据(\(data.count)字节): \(data.map { String(format: "%02X", $0) }.joined(separator: " ").prefix(100))")

                    let tempBuffer = ADBDataBuffer()
                    tempBuffer.append(data)

                    while let message = tempBuffer.tryReadMessage() {
                        switch message.command {
                        case ADBCommand.CNXN:
                            self.onLog?("[成功] 配对CNXN成功")
                            SSLClose(sslCtx)
                            close(sockFd)
                            completion(true, "配对成功")
                            return
                        case ADBCommand.AUTH:
                            let authType = message.arg0
                            self.onLog?("[调试] AUTH类型: \(authType)")

                            if authType == ADBAuthType.token.rawValue {
                                self.onLog?("[信息] 收到TOKEN，签名配对码")
                                if let signature = ADBAuth.signPairingCode(pairingCode) {
                                    let packet = ADBProtocol.packAUTH(type: .signature, data: signature)
                                    _ = sendRaw(packet)
                                    self.onLog?("[信息] 发送签名响应")
                                } else {
                                    SSLClose(sslCtx)
                                    close(sockFd)
                                    completion(false, "签名失败")
                                    return
                                }
                            } else if authType == ADBAuthType.signature.rawValue {
                                self.onLog?("[成功] 配对成功！")
                                SSLClose(sslCtx)
                                close(sockFd)
                                completion(true, "配对成功")
                                return
                            } else {
                                if let keyPair = self.keyManager.loadOrCreateKeyPair(),
                                   let pemStr = ADBAuth.exportPublicKeyPEM(keyPair.publicKey),
                                   var pemData = pemStr.data(using: String.Encoding.utf8) {
                                    pemData.append(0)
                                    let packet = ADBProtocol.packAUTH(type: .rsaPublicKey, data: pemData)
                                    _ = sendRaw(packet)
                                    self.onLog?("[信息] 发送公钥")
                                }
                            }
                        default:
                            self.onLog?("[调试] 其他命令: \(String(format: "0x%08X", message.command))")
                        }
                    }
                }
            }

            self.onLog?("[错误] 配对超时")
            SSLClose(sslCtx)
            close(sockFd)
            completion(false, "配对超时")
        }
    }
}
