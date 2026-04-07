import Foundation
import Network

enum ADBClientState {
    case disconnected
    case connecting
    case authenticating
    case connected
    case failed(String)
}

@MainActor
class ADBClient: ObservableObject {
    @Published var state: ADBClientState = .disconnected
    @Published var deviceInfo: ADBDevice?

    private let tcpClient = TCPClient()
    private let dataBuffer = ADBDataBuffer()
    private let channelManager = ADBChannelManager()
    private let keyManager = ADBKeyManager()
    private var authRetries = 0
    private let maxAuthRetries = 3

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    init() {
        tcpClient.onStateChanged = { [weak self] tcpState in
            Task { @MainActor in
                self?.handleTCPStateChange(tcpState)
            }
        }
        tcpClient.onDataReceived = { [weak self] data in
            self?.handleIncomingData(data)
        }
    }

    func connect(host: String, port: UInt16 = 5555) {
        guard case .disconnected = state || case .failed = state else { return }
        updateState(.connecting)
        tcpClient.connect(host: host, port: port)
    }

    func disconnect() {
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
        state = newState
    }

    private func handleTCPStateChange(_ tcpState: TCPClientState) {
        switch tcpState {
        case .connected:
            sendCNXN()
        case .disconnected:
            channelManager.removeAllChannels()
            updateState(.disconnected)
        case .failed(let error):
            updateState(.failed(error.localizedDescription))
        case .connecting:
            updateState(.connecting)
        }
    }

    private func sendCNXN() {
        updateState(.authenticating)
        authRetries = 0
        let packet = ADBProtocol.packCNXN()
        tcpClient.send(data: packet)
        Logger.info("发送CNXN握手", category: "ADBClient")
    }

    private func handleIncomingData(_ data: Data) {
        dataBuffer.append(data)

        while let message = dataBuffer.tryReadMessage() {
            guard ADBProtocol.validateMessage(message) else {
                Logger.warning("收到无效ADB消息", category: "ADBClient")
                continue
            }
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
        Logger.info("设备已连接, 特性: \(features)", category: "ADBClient")
        updateState(.connected)
    }

    private func handleAUTH(_ message: ADBMessage) {
        let authType = message.arg0

        switch authType {
        case ADBAuthType.token.rawValue:
            handleAuthToken(message.data)
        case ADBAuthType.signature.rawValue:
            authRetries += 1
            if authRetries < maxAuthRetries {
                handleAuthToken(message.data)
            } else {
                sendPublicKey()
            }
        default:
            sendPublicKey()
        }
    }

    private func handleAuthToken(_ tokenData: Data) {
        guard let keyPair = keyManager.loadOrCreateKeyPair() else {
            Logger.error("无法获取RSA密钥对", category: "ADBClient")
            sendPublicKey()
            return
        }

        guard let signature = ADBAuth.signToken(token: tokenData, privateKey: keyPair.privateKey) else {
            Logger.error("签名失败，发送公钥", category: "ADBClient")
            sendPublicKey()
            return
        }

        let packet = ADBProtocol.packAUTH(type: .signature, data: signature)
        tcpClient.send(data: packet)
        Logger.info("发送AUTH签名", category: "ADBClient")
    }

    private func sendPublicKey() {
        guard let pemString = keyManager.getPublicKeyPEM() else {
            Logger.error("无法导出公钥PEM", category: "ADBClient")
            updateState(.failed("认证失败：无法导出公钥"))
            return
        }

        guard var pemData = pemString.data(using: .utf8) else { return }
        pemData.append(0)

        let packet = ADBProtocol.packAUTH(type: .rsaPublicKey, data: pemData)
        tcpClient.send(data: packet)
        Logger.info("发送公钥", category: "ADBClient")
    }

    private func handleOKAY(_ message: ADBMessage) {
        let remoteId = message.arg0
        let localId = message.arg1

        if let channel = channelManager.getChannel(localId: localId) {
            if channel.state == .opening {
                channel.remoteId = remoteId
                channel.state = .open
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
}
