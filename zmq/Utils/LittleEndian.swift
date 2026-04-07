import Foundation

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: MemoryLayout<UInt32>.size))
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: MemoryLayout<UInt64>.size))
    }

    mutating func appendBigEndian(_ value: UInt32) {
        var big = value.bigEndian
        append(Data(bytes: &big, count: MemoryLayout<UInt32>.size))
    }

    mutating func appendBigEndian(_ value: UInt64) {
        var big = value.bigEndian
        append(Data(bytes: &big, count: MemoryLayout<UInt64>.size))
    }

    func readLittleEndianUInt16(at offset: Int) -> UInt16 {
        guard offset + MemoryLayout<UInt16>.size <= count else { return 0 }
        return self[offset..<offset + MemoryLayout<UInt16>.size].withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }

    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        guard offset + MemoryLayout<UInt32>.size <= count else { return 0 }
        return self[offset..<offset + MemoryLayout<UInt32>.size].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }

    func readLittleEndianUInt64(at offset: Int) -> UInt64 {
        guard offset + MemoryLayout<UInt64>.size <= count else { return 0 }
        return self[offset..<offset + MemoryLayout<UInt64>.size].withUnsafeBytes { $0.load(as: UInt64.self) }.littleEndian
    }

    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        guard offset + MemoryLayout<UInt32>.size <= count else { return 0 }
        return self[offset..<offset + MemoryLayout<UInt32>.size].withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    func readBigEndianUInt64(at offset: Int) -> UInt64 {
        guard offset + MemoryLayout<UInt64>.size <= count else { return 0 }
        return self[offset..<offset + MemoryLayout<UInt64>.size].withUnsafeBytes { $0.load(as: UInt64.self) }.bigEndian
    }
}
