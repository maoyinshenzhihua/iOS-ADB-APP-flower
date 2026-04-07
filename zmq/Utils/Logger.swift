import Foundation
import os.log

struct Logger {
    private static let subsystem = "com.zmq.app"

    static func debug(_ message: String, category: String = "General") {
        let log = OSLog(subsystem: subsystem, category: category)
        os_log(.debug, log: log, "%{public}@", message)
    }

    static func info(_ message: String, category: String = "General") {
        let log = OSLog(subsystem: subsystem, category: category)
        os_log(.info, log: log, "%{public}@", message)
    }

    static func error(_ message: String, category: String = "General") {
        let log = OSLog(subsystem: subsystem, category: category)
        os_log(.error, log: log, "%{public}@", message)
    }

    static func warning(_ message: String, category: String = "General") {
        let log = OSLog(subsystem: subsystem, category: category)
        os_log(.default, log: log, "%{public}@", message)
    }
}
