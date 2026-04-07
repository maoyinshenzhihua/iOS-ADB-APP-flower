import Foundation

struct FileInfo: Identifiable {
    let id = UUID()
    var name: String
    var path: String
    var mode: UInt32 = 0
    var size: UInt64 = 0
    var modifiedTime: Date = Date()
    var isDirectory: Bool {
        (mode & 0xF000) == 0x4000
    }
    var isFile: Bool {
        (mode & 0xF000) == 0x8000
    }
    var isSymlink: Bool {
        (mode & 0xF000) == 0xA000
    }
    var permissionString: String {
        let perms = mode & 0x0FFF
        return String(format: "%o", perms)
    }
    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
