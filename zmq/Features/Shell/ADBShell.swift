import Foundation

class ADBShell {
    private let client: ADBClient

    init(client: ADBClient) {
        self.client = client
    }

    func executeCommand(_ command: String, timeout: TimeInterval = 30) -> String? {
        let destination = "shell:\(command)\0"
        guard let channel = client.openChannel(destination: destination) else { return nil }

        var output = Data()
        var result: String?
        let lock = NSLock()

        channel.onDataReceived = { data in
            lock.lock()
            output.append(data)
            lock.unlock()
        }

        channel.onClosed = {
            lock.lock()
            result = String(data: output, encoding: .utf8)
            lock.unlock()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if !channel.isClosed {
                self.client.closeChannel(channel)
                lock.lock()
                result = String(data: output, encoding: .utf8)
                lock.unlock()
            }
        }

        return result
    }

    func openInteractiveShell() -> ADBChannel? {
        let destination = "shell:\0"
        return client.openChannel(destination: destination)
    }
}
