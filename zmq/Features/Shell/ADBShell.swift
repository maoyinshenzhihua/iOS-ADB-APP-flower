import Foundation

class ADBShell {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func executeCommand(_ command: String) async -> String? {
        var receivedData = Data()
        let destination = "shell: \(command)"

        Logger.info("执行shell命令: \(destination)", category: "ADBShell")

        guard let channel = client.openChannel(destination: destination) else {
            Logger.error("无法打开shell通道", category: "ADBShell")
            return nil
        }

        channel.onDataReceived = { data in
            Logger.info("收到shell数据: \(data.count) 字节", category: "ADBShell")
            receivedData.append(data)
        }

        // 等待通道建立
        Logger.info("等待shell通道打开...", category: "ADBShell")
        let opened = await channel.waitForOpen()
        if !opened {
            Logger.error("shell通道建立超时", category: "ADBShell")
            return nil
        }
        Logger.info("shell通道已打开", category: "ADBShell")

        // 等待数据接收完成（等待2秒让数据到达）
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        Logger.info("收到shell数据大小: \(receivedData.count)", category: "ADBShell")

        // 关闭通道
        channel.close()

        if receivedData.isEmpty {
            Logger.warning("shell命令无输出", category: "ADBShell")
            return nil
        }

        let output = String(data: receivedData, encoding: .utf8) ?? ""
        Logger.info("shell输出: \(output.prefix(100))", category: "ADBShell")
        return output
    }

    func openInteractiveShell() -> ADBChannel? {
        let destination = "shell:\0"
        return client.openChannel(destination: destination)
    }
}
