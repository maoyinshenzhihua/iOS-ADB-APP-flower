import Foundation

enum ADBCommand {
    static let CNXN: UInt32 = 0x4e584e43
    static let AUTH: UInt32 = 0x48545541
    static let OPEN: UInt32 = 0x4e45504f
    static let OKAY: UInt32 = 0x59414b4f
    static let CLSE: UInt32 = 0x45534c43
    static let WRTE: UInt32 = 0x45545257
    static let SYNC: UInt32 = 0x434e5953
}

enum ADBAuthType: UInt32 {
    case token = 1
    case signature = 2
    case rsaPublicKey = 3
}

enum ADBSyncCommand {
    static let STAT: UInt32 = 0x54415453
    static let LIST: UInt32 = 0x5453494c
    static let SEND: UInt32 = 0x444e4553
    static let RECV: UInt32 = 0x56434552
    static let DENT: UInt32 = 0x544e4544
    static let DONE: UInt32 = 0x454e4f44
    static let DATA: UInt32 = 0x41544144
    static let OKAY: UInt32 = 0x59414b4f
    static let FAIL: UInt32 = 0x4c494146
    static let QUIT: UInt32 = 0x54495551
}

let ADB_VERSION: UInt32 = 0x01000000
let MAX_PAYLOAD: UInt32 = 262144
let ADB_HEADER_SIZE = 24

let ADB_FEATURES = "host::features=cmd,shell_v2,ls_v2,stat_v2,fixed_push_mkdir,sendrecv_v2\n"

let ADB_SYNC_MAX_BLOCK_SIZE: UInt32 = 65536

enum ADBKeyCode: Int {
    case home = 3
    case back = 4
    case call = 5
    case endcall = 6
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case camera = 27
    case menu = 82
    case appSwitch = 187
    case enter = 66
    case del = 67
    case tab = 61
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
}
