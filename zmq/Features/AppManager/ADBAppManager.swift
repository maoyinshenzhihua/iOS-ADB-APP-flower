import Foundation

class ADBAppManager {
    private let shell: ADBShell

    init(shell: ADBShell) {
        self.shell = shell
    }

    func listThirdPartyApps() async -> [AppInfo] {
        await listApps(filter: "-3")
    }

    func listAllApps() async -> [AppInfo] {
        await listApps(filter: "")
    }

    func listSystemApps() async -> [AppInfo] {
        await listApps(filter: "-s")
    }

    private func listApps(filter: String) async -> [AppInfo] {
        let command = filter.isEmpty ? "pm list packages" : "pm list packages \(filter)"
        guard let output = await shell.executeCommand(command) else { return [] }

        return output.split(separator: "\n").compactMap { line -> AppInfo? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("package:") else { return nil }
            let packageName = String(trimmed.dropFirst("package:".count))
            return AppInfo(packageName: packageName, isSystemApp: filter == "-s")
        }
    }

    func launchApp(packageName: String, activity: String) async -> Bool {
        let command = "am start -n \(packageName)/\(activity)"
        let result = await shell.executeCommand(command)
        return result?.contains("Starting:") == true
    }

    func uninstallApp(packageName: String) async -> Bool {
        let command = "pm uninstall \(packageName)"
        let result = await shell.executeCommand(command)
        return result?.trimmingCharacters(in: .whitespacesAndNewlines) == "Success"
    }

    func forceStop(packageName: String) async {
        _ = await shell.executeCommand("am force-stop \(packageName)")
    }

    func clearData(packageName: String) async -> Bool {
        let result = await shell.executeCommand("pm clear \(packageName)")
        return result?.trimmingCharacters(in: .whitespacesAndNewlines) == "Success"
    }
}
