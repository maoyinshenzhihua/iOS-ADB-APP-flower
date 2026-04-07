import Foundation

struct ADBDevice: Identifiable {
    let id = UUID()
    var host: String
    var port: UInt16 = 5555
    var name: String = ""
    var model: String = ""
    var androidVersion: String = ""
    var resolution: String = ""
    var cpu: String = ""
    var memory: String = ""
    var serialNo: String = ""
    var isConnected: Bool = false

    var displayAddress: String {
        "\(host):\(port)"
    }
}
