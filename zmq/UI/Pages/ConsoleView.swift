import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var adbClient: ADBClient
    @State private var command = ""
    @State private var output: [String] = []
    @State private var isExecuting = false

    private let quickCommands = [
        ("设备信息", "getprop ro.product.model"),
        ("分辨率", "wm size"),
        ("内存", "cat /proc/meminfo | head -3"),
        ("CPU", "cat /proc/cpuinfo | head -5"),
        ("应用列表", "pm list packages -3"),
        ("电池", "dumpsys battery"),
        ("IP地址", "ip addr show wlan0"),
        ("重启", "reboot"),
    ]

    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .id(index)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .onChange(of: output.count) { _ in
                            proxy.scrollTo(output.count - 1, anchor: .bottom)
                        }
                    }

                    Divider()

                    VStack(spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickCommands, id: \.0) { name, cmd in
                                    Button(name) {
                                        executeCommand(cmd)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal)
                        }

                        HStack {
                            TextField("输入ADB命令", text: $command)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.body, design: .monospaced))
                                .onSubmit { executeCurrentCommand() }

                            Button(action: executeCurrentCommand) {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .disabled(command.isEmpty || isExecuting)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }
                }
                .navigationTitle("控制台")
                .toolbar {
                    Button("清空") {
                        output.removeAll()
                    }
                }
                
                // 透明覆盖层，用于捕获点击事件
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            }
        }
    }

    private func executeCurrentCommand() {
        guard !command.isEmpty else { return }
        let cmd = command
        command = ""
        executeCommand(cmd)
    }

    private func executeCommand(_ cmd: String) {
        guard adbClient.isConnected else {
            output.append("[错误] 未连接设备")
            return
        }

        output.append("$ \(cmd)")
        isExecuting = true

        let shell = ADBShell(client: adbClient)

        Task {
            let result = await shell.executeCommand(cmd)
            await MainActor.run {
                if let result = result {
                    let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    output.append(contentsOf: lines)
                } else {
                    output.append("[无输出]")
                }
                isExecuting = false
            }
        }
    }
}
