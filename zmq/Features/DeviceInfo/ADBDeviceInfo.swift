import Foundation

class ADBDeviceInfo {
    private let shell: ADBShell

    init(shell: ADBShell) {
        self.shell = shell
    }

    func getModel() async -> String {
        (await shell.executeCommand("getprop ro.product.model"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知"
    }

    func getAndroidVersion() async -> String {
        (await shell.executeCommand("getprop ro.build.version.release"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知"
    }

    func getResolution() async -> String {
        (await shell.executeCommand("wm size"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知"
    }

    func getCPU() async -> String {
        (await shell.executeCommand("getprop ro.product.cpu.abi"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知"
    }

    func getMemory() async -> String {
        (await shell.executeCommand("cat /proc/meminfo | head -1"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知"
    }

    func getSerialNo() async -> String {
        (await shell.executeCommand("getprop ro.serialno"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未知"
    }

    func getAllInfo() async -> ADBDevice {
        async let model = getModel()
        async let version = getAndroidVersion()
        async let resolution = getResolution()
        async let cpu = getCPU()
        async let memory = getMemory()
        async let serial = getSerialNo()

        var device = ADBDevice()
        device.model = await model
        device.androidVersion = await version
        device.resolution = await resolution
        device.cpu = await cpu
        device.memory = await memory
        device.serialNo = await serial
        return device
    }
}
