import Foundation

class ADBShell {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func executeCommand(_ command: String) async -> String? {
        guard client.isConnected else { return nil }

        let destination = "shell:\(command)\0"
        guard let channel = client.openChannel(destination: destination) else { return nil }

        return await withCheckedContinuation { continuation in
            var output = Data()

            channel.onDataReceived = { data in
                output.append(data)
            }

            channel.onClosed = {
                let result = String(data: output, encoding: .utf8)
                continuation.resume(returning: result)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if !channel.isClosed {
                    client.closeChannel(channel)
                    let result = String(data: output, encoding: .utf8)
                    continuation.resume(returning: result)
                }
            }
        }
    }

    func openInteractiveShell() -> ADBChannel? {
        guard client.isConnected else { return nil }
        let destination = "shell:\0"
        return client.openChannel(destination: destination)
    }
}
