import Foundation
import Network

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

    var onStateChanged: ((TCPClientState) -> Void)?
    var onDataReceived: ((Data) -> Void)?

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    func connect(host: String, port: UInt16 = 5555) {
        self.host = host
        self.port = port
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

        connection = NWConnection(host: endpointHost, port: endpointPort, using: parameters)
        connection?.stateUpdateHandler = { [weak self] newState in
            self?.handleStateUpdate(newState)
        }
        connection?.start(queue: queue)

        updateState(.connecting)
        Logger.info("正在连接 \(host):\(port)", category: "TCPClient")
    }

    func disconnect() {
        reconnectAttempts = -1
        connection?.cancel()
        connection = nil
        updateState(.disconnected)
        Logger.info("已断开连接", category: "TCPClient")
    }

    func reconnect() {
        guard reconnectAttempts >= 0 else { return }
        let delay = min(pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        reconnectAttempts += 1
        Logger.info("将在 \(delay)秒后重连 (第\(reconnectAttempts)次)", category: "TCPClient")

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.reconnectAttempts >= 0 else { return }
            self.connect(host: self.host, port: self.port)
        }
    }

    func send(data: Data) {
        guard let connection = connection, isConnected else {
            Logger.error("发送失败：未连接", category: "TCPClient")
            return
        }

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                Logger.error("发送数据失败: \(error)", category: "TCPClient")
                self?.updateState(.failed(error))
            }
        })
    }

    private func receive() {
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144 + ADB_HEADER_SIZE) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.onDataReceived?(data)
            }

            if let error = error {
                Logger.error("接收数据错误: \(error)", category: "TCPClient")
                self?.updateState(.failed(error))
                return
            }

            if isComplete {
                Logger.info("连接已关闭", category: "TCPClient")
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
