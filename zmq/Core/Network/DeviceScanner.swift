import Foundation
import Network

class DeviceScanner {
    private var scanning = false
    private let queue = DispatchQueue(label: "com.zmq.scanner", qos: .userInitiated, attributes: .concurrent)

    var onDeviceFound: ((String, String) -> Void)?

    func startScan(subnet: String = "192.168.1") {
        guard !scanning else { return }
        scanning = true
        Logger.info("开始扫描局域网设备: \(subnet).*", category: "DeviceScanner")

        let group = DispatchGroup()

        for i in 1...255 {
            guard scanning else { break }
            let ip = "\(subnet).\(i)"
            group.enter()

            queue.async { [weak self] in
                guard let self = self, self.scanning else {
                    group.leave()
                    return
                }
                if self.tryConnect(ip: ip, port: 5555, timeout: 1.5) {
                    let deviceName = self.probeDevice(ip: ip)
                    DispatchQueue.main.async {
                        self.onDeviceFound?(ip, deviceName)
                    }
                    Logger.info("发现设备: \(ip) - \(deviceName)", category: "DeviceScanner")
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.scanning = false
            Logger.info("局域网扫描完成", category: "DeviceScanner")
        }
    }

    func stopScan() {
        scanning = false
    }

    private func tryConnect(ip: String, port: UInt16, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var connected = false

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }
        let host = NWEndpoint.Host(ip)
        let connection = NWConnection(host: host, port: endpointPort, using: .tcp)

        let stateQueue = DispatchQueue(label: "com.zmq.scan.\(ip)")
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connected = true
                connection.cancel()
                semaphore.signal()
            case .failed, .cancelled:
                connected = false
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: stateQueue)

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            connection.cancel()
        }

        return connected
    }

    private func probeDevice(ip: String) -> String {
        return "Android Device"
    }

    static func getLocalSubnet() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }

        guard let ip = address else { return nil }
        let components = ip.split(separator: ".")
        guard components.count >= 3 else { return nil }
        return "\(components[0]).\(components[1]).\(components[2])"
    }
}
