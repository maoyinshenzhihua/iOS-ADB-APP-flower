import Foundation
import Network
import Security

enum TCPClientState {
    case disconnected
    case connecting
    case connected
    case failed(Error)
}

class TCPClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.zmq.tcpclient", qos: .userInitiated)
    private var state: TCPClientState = .disconnected
    private var reconnectAttempts: Int = 0
    private let maxReconnectDelay: TimeInterval = 30
    private var host: String = ""
    private var port: UInt16 = 5555
    private var useTLS = false

    var onStateChanged: ((TCPClientState) -> Void)?
    var onDataReceived: ((Data) -> Void)?
    var onLog: ((String) -> Void)?

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    func connect(host: String, port: UInt16 = 5555, useTLS: Bool = false) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.reconnectAttempts = 0

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            Logger.error("无效端口: \(port)", category: "TCPClient")
            return
        }

        let endpointHost = NWEndpoint.Host(host)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 10
        tcpOptions.noDelay = true

        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.transportProtocol = tcpOptions

        if useTLS {
            let tlsParameters = NWParameters(tls: NWProtocolTLS.Options())
            tlsParameters.defaultProtocolStack.transportProtocol = tcpOptions

            if let tlsOpts = tlsParameters.defaultProtocolStack.applicationProtocols.first as? NWProtocolTLS.Options {
                sec_protocol_options_set_verify_block(tlsOpts.securityProtocolOptions, { _, _, completionHandler in
                    completionHandler(true)
                }, queue)
            }

            connection = NWConnection(host: endpointHost, port: endpointPort, using: tlsParameters)
        } else {
            connection = NWConnection(host: endpointHost, port: endpointPort, using: parameters)
        }
        connection?.stateUpdateHandler = { [weak self] newState in
            self?.handleStateUpdate(newState)
        }
        connection?.start(queue: queue)

        updateState(.connecting)
        Logger.info("正在连接 \(host):\(port) TLS=\(useTLS)", category: "TCPClient")
        onLog?("正在连接 \(host):\(port)")
    }

    func reconnect() {
        guard reconnectAttempts >= 0 else { return }
        let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        reconnectAttempts += 1
        Logger.info("将在 \(delay)秒后重连 (第\(reconnectAttempts)次)", category: "TCPClient")
        onLog?("将在 \(delay)秒后重连 (第\(reconnectAttempts)次)")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.reconnectAttempts >= 0 else { return }
            self.connect(host: self.host, port: self.port, useTLS: self.useTLS)
        }
    }
    
    func disconnect() {
        reconnectAttempts = -1
        connection?.cancel()
        connection = nil
        updateState(.disconnected)
        Logger.info("已断开连接", category: "TCPClient")
        onLog?("已断开连接")
    }

    func send(data: Data) {
        guard let connection = connection, isConnected else {
            Logger.error("发送失败：未连接", category: "TCPClient")
            onLog?("[错误] 发送失败：未连接")
            return
        }
        
        // 打印发送的十六进制数据
        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        Logger.info("发送 \(data.count) 字节: \(hexString.prefix(100))...", category: "TCPClient")
        onLog?("发送 \(data.count) 字节: \(hexString.prefix(200))")

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                Logger.error("发送数据失败: \(error)", category: "TCPClient")
                self?.onLog?("[错误] 发送失败: \(error.localizedDescription)")
                self?.updateState(.failed(error))
            } else {
                Logger.info("发送完成", category: "TCPClient")
                self?.onLog?("发送完成")
            }
        })
    }

    private func receive() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144 + ADB_HEADER_SIZE) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                Logger.info("收到 \(data.count) 字节: \(hexString.prefix(100))...", category: "TCPClient")
                self?.onLog?("收到 \(data.count) 字节: \(hexString.prefix(200))")
                self?.onDataReceived?(data)
            } else {
                Logger.info("收到空数据", category: "TCPClient")
                self?.onLog?("收到空数据")
            }

            if let error = error {
                Logger.error("接收数据错误: \(error)", category: "TCPClient")
                self?.onLog?("[错误] 接收数据错误: \(error.localizedDescription)")
                self?.updateState(.failed(error))
                return
            }

            if isComplete {
                Logger.info("连接已关闭", category: "TCPClient")
                self?.onLog?("连接已关闭")
                self?.updateState(.disconnected)
                self?.reconnect()
                return
            }

            self?.receive()
        }
    }

    private func handleStateUpdate(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            reconnectAttempts = 0
            updateState(.connected)
            Logger.info("连接成功 \(host):\(port)", category: "TCPClient")
            onLog?("TCP连接成功")
            receive()
        case .waiting(let error):
            Logger.warning("连接等待: \(error)", category: "TCPClient")
        case .failed(let error):
            Logger.error("连接失败: \(error)", category: "TCPClient")
            updateState(.failed(error))
            reconnect()
        case .cancelled:
            updateState(.disconnected)
        default:
            break
        }
    }

    private func updateState(_ newState: TCPClientState) {
        state = newState
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onStateChanged?(self.state)
        }
    }
}
