import Foundation

class ADBRemoteControl {
    private let shell: ADBShell

    init(shell: ADBShell) {
        self.shell = shell
    }

    func tap(x: Int, y: Int) async {
        _ = await shell.executeCommand("input tap \(x) \(y)")
    }

    func swipe(x1: Int, y1: Int, x2: Int, y2: Int, duration: Int = 300) async {
        _ = await shell.executeCommand("input swipe \(x1) \(y1) \(x2) \(y2) \(duration)")
    }

    func keyEvent(keyCode: ADBKeyCode) async {
        _ = await shell.executeCommand("input keyevent \(keyCode.rawValue)")
    }

    func keyEvent(keyCode: Int) async {
        _ = await shell.executeCommand("input keyevent \(keyCode)")
    }

    func text(_ input: String) async {
        let escaped = input.replacingOccurrences(of: " ", with: "%s")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
        _ = await shell.executeCommand("input text \"\(escaped)\"")
    }

    func longPress(x: Int, y: Int, duration: Int = 1000) async {
        _ = await shell.executeCommand("input swipe \(x) \(y) \(x) \(y) \(duration)")
    }

    func pressHome() async {
        await keyEvent(keyCode: .home)
    }

    func pressBack() async {
        await keyEvent(keyCode: .back)
    }

    func pressPower() async {
        await keyEvent(keyCode: .power)
    }

    func pressVolumeUp() async {
        await keyEvent(keyCode: .volumeUp)
    }

    func pressVolumeDown() async {
        await keyEvent(keyCode: .volumeDown)
    }

    func openNotifications() async {
        _ = await shell.executeCommand("input swipe 540 0 540 500 300")
    }

    func openQuickSettings() async {
        _ = await shell.executeCommand("input swipe 540 0 540 800 300")
    }
}
