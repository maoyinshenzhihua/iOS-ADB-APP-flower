import Foundation

struct AppInfo: Identifiable {
    let id = UUID()
    var packageName: String
    var isSystemApp: Bool = false

    var displayName: String {
        packageName.components(separatedBy: ".").last ?? packageName
    }
}
