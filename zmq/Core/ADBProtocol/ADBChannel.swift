import Foundation

enum ADBChannelState {
    case idle
    case opening
    case open
    case closed
}

class ADBChannel {
    let localId: UInt32
    var remoteId: UInt32 = 0
    var state: ADBChannelState = .idle
    var destination: String = ""
    var onDataReceived: ((Data) -> Void)?
    var onClosed: (() -> Void)?

    init(localId: UInt32) {
        self.localId = localId
    }

    var isOpen: Bool { state == .open }
    var isClosed: Bool { state == .closed }
}

class ADBChannelManager {
    private var nextLocalId: UInt32 = 1
    private var channels: [UInt32: ADBChannel] = [:]
    private let lock = NSLock()

    func createChannel() -> ADBChannel {
        lock.lock()
        defer { lock.unlock() }
        let channel = ADBChannel(localId: nextLocalId)
        nextLocalId += 1
        channels[channel.localId] = channel
        return channel
    }

    func getChannel(localId: UInt32) -> ADBChannel? {
        lock.lock()
        defer { lock.unlock() }
        return channels[localId]
    }

    func getChannelByRemoteId(remoteId: UInt32) -> ADBChannel? {
        lock.lock()
        defer { lock.unlock() }
        return channels.values.first { $0.remoteId == remoteId }
    }

    func closeChannel(localId: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        if let channel = channels[localId] {
            channel.state = .closed
            channel.onClosed?()
            channels.removeValue(forKey: localId)
        }
    }

    func removeAllChannels() {
        lock.lock()
        defer { lock.unlock() }
        for (_, channel) in channels {
            channel.state = .closed
            channel.onClosed?()
        }
        channels.removeAll()
    }

    var allChannels: [ADBChannel] {
        lock.lock()
        defer { lock.unlock() }
        return Array(channels.values)
    }
}
