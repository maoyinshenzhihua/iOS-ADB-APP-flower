import Foundation

class ADBShell {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func executeCommand(_ command: String) async -> String? {
        var receivedData = Data()
        let commandData = "\(command)\n".data(using: .utf8)!

        let channel = client.openChannel(destination: "shell: \(command)") { data in
            receivedData.append(data)
        }

        guard let channel = channel else {
            Logger.error("无法打开shell通道", category: "ADBShell")
            return nil
        }

        // 等待通道建立
        let opened = await channel.waitForOpen()
        if !opened {
            Logger.error("shell通道建立超时", category: "ADBShell")
            return nil
        }

        // 等待数据接收完成（等待1秒让数据到达）
        try? await Task.sleep(nanoseconds: 1_000_000_000)

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
