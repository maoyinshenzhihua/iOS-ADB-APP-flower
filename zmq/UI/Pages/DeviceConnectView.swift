import SwiftUI

struct DeviceConnectView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var host = ""
    @State private var port = "5555"
    @State private var isScanning = false
    @State private var discoveredDevices: [(String, String)] = []

    private let scanner = DeviceScanner()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("手动连接")) {
                    HStack {
                        TextField("IP地址", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.decimalPad)

                        TextField("端口", text: $port)
                            .frame(width: 70)
                            .keyboardType(.numberPad)
                    }

                    Button(action: connectToDevice) {
                        HStack {
                            Spacer()
                            if case .connecting = adbClient.state {
                                ProgressView()
                            } else {
                                Text("连接")
                            }
                            Spacer()
                        }
                    }
                    .disabled(host.isEmpty || isConnecting)
                }

                Section(header: Text("局域网扫描")) {
                    Button(action: startScan) {
                        HStack {
                            Text(isScanning ? "扫描中..." : "扫描设备")
                            if isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isScanning)

                    ForEach(discoveredDevices, id: \.0) { ip, name in
                        Button(action: { connectTo(ip: ip) }) {
                            HStack {
                                Image(systemName: "iphone.and.arrow.forward")
                                VStack(alignment: .leading) {
                                    Text(name)
                                    Text(ip)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                }

                Section(header: Text("连接状态")) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                        Text(statusText)
                    }

                    if adbClient.isConnected {
                        Button("断开连接", role: .destructive) {
                            adbClient.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("设备连接")
        }
    }

    private var isConnecting: Bool {
        if case .connecting = adbClient.state { return true }
        return false
    }

    private var statusColor: Color {
        switch adbClient.state {
        case .connected: return .green
        case .connecting, .authenticating: return .yellow
        case .disconnected: return .gray
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch adbClient.state {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .authenticating: return "认证中..."
        case .connected: return "已连接"
        case .failed(let msg): return "连接失败: \(msg)"
        }
    }

    private func connectToDevice() {
        // 收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        guard let portNum = UInt16(port) else { return }
        adbClient.connect(host: host, port: portNum)
    }

    private func connectTo(ip: String) {
        // 收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        host = ip
        port = "5555"
        adbClient.connect(host: ip, port: 5555)
    }

    private func startScan() {
        // 收起键盘
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        discoveredDevices.removeAll()
        isScanning = true

        scanner.onDeviceFound = { ip, name in
            DispatchQueue.main.async {
                if !self.discoveredDevices.contains(where: { $0.0 == ip }) {
                    self.discoveredDevices.append((ip, name))
                }
            }
        }

        let subnet = DeviceScanner.getLocalSubnet() ?? "192.168.1"
        scanner.startScan(subnet: subnet)

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.isScanning = false
        }
    }
}
