import Foundation

class ADBShell {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func executeCommand(_ command: String) async -> String? {
        var receivedData = Data()
        let destination = "shell: \(command)"

        guard let channel = client.openChannel(destination: destination) else {
            return nil
        }

        channel.onDataReceived = { data in
            receivedData.append(data)
        }

        let opened = await channel.waitForOpen()
        if !opened {
            return nil
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        channel.close()

        if receivedData.isEmpty {
            return nil
        }

        return String(data: receivedData, encoding: .utf8)
    }

    func openInteractiveShell() -> ADBChannel? {
        return client.openChannel(destination: "shell:")
    }
}