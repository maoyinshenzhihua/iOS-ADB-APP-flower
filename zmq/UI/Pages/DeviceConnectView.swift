import SwiftUI

struct DeviceConnectView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var host = ""
    @State private var port = "5555"
    @State private var isScanning = false
    @State private var discoveredDevices: [(String, String)] = []
    @State private var connectionLog: [String] = []
    @State private var showLog = false

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

                    if adbClient.isConnected {
                        // 已连接：显示"断开连接"
                        Button(action: adbClient.disconnect) {
                            HStack {
                                Spacer()
                                Text("断开连接")
                                Spacer()
                            }
                        }
                    } else if case .connecting = adbClient.state {
                        // 正在连接：显示"取消连接"
                        Button(action: adbClient.disconnect) {
                            HStack {
                                Spacer()
                                Text("取消连接")
                                Spacer()
                            }
                        }
                    } else {
                        // 未连接：显示"连接"
                        Button(action: connectToDevice) {
                            HStack {
                                Spacer()
                                Text("连接")
                                Spacer()
                            }
                        }
                        .disabled(host.isEmpty)
                    }
                }

                Section(header: Text("局域网扫描")) {
                    Button(action: isScanning ? stopScan : startScan) {
                        HStack {
                            Text(isScanning ? "停止扫描" : "扫描设备")
                            if isScanning {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }

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
                        // 连接详细信息
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("连接地址:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(host):\(port)")
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("连接时间:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("刚刚")
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("ADB 版本:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("1.0.41")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Button("断开连接", role: .destructive) {
                            adbClient.disconnect()
                        }
                    }
                }
                
                // 日志显示
                if showLog && !connectionLog.isEmpty {
                    Section(header: HStack {
                        Text("连接日志")
                        Spacer()
                        Button("清空") {
                            connectionLog.removeAll()
                        }
                        .font(.caption)
                    }) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(connectionLog.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(logColor(for: line))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            .navigationTitle("设备连接")
            .toolbar {
                Button(showLog ? "隐藏日志" : "显示日志") {
                    showLog.toggle()
                }
            }
            .onAppear {
                adbClient.onLog = { [weak self] message in
                    DispatchQueue.main.async {
                        self?.addLog(message)
                    }
                }
            }
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
    
    private func stopScan() {
        isScanning = false
        // 这里可以添加停止扫描的逻辑
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        connectionLog.append("[\(timestamp)] \(message)")
    }
    
    private func logColor(for line: String) -> Color {
        if line.contains("[错误]") || line.contains("失败") {
            return .red
        } else if line.contains("[警告]") || line.contains("失败") {
            return .orange
        } else if line.contains("[成功]") || line.contains("已连接") {
            return .green
        } else if line.contains("[信息]") || line.contains("发送") || line.contains("收到") {
            return .blue
        }
        return .primary
    }
}
