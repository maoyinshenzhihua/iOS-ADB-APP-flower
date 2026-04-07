import Foundation

class ADBFileTransfer {
    private let fileSync: ADBFileSync
    private let shell: ADBShell

    init(fileSync: ADBFileSync, shell: ADBShell) {
        self.fileSync = fileSync
        self.shell = shell
    }

    func pushFile(localURL: URL, remotePath: String, progress: ((Float) -> Void)? = nil) -> Bool {
        return fileSync.push(localURL: localURL, remotePath: remotePath, progress: progress)
    }

    func pullFile(remotePath: String, localURL: URL, progress: ((Float) -> Void)? = nil) -> Bool {
        return fileSync.pull(remotePath: remotePath, localURL: localURL, progress: progress)
    }

    func deleteFile(path: String) -> Bool {
        let result = shell.executeCommand("rm -rf '\(path)'")
        return result?.isEmpty ?? true
    }

    func createDirectory(path: String) -> Bool {
        let result = shell.executeCommand("mkdir -p '\(path)'")
        return result?.isEmpty ?? true
    }

    func rename(oldPath: String, newPath: String) -> Bool {
        let result = shell.executeCommand("mv '\(oldPath)' '\(newPath)'")
        return result?.isEmpty ?? true
    }

    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func localPathForRemote(_ remotePath: String) -> URL {
        let docsDir = getDocumentsDirectory()
        let relativePath = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return docsDir.appendingPathComponent(relativePath)
    }

    func pushToSandbox(localURL: URL, remotePath: String, progress: ((Float) -> Void)? = nil) -> Bool {
        return fileSync.push(localURL: localURL, remotePath: remotePath, progress: progress)
    }

    func pullFromSandbox(remotePath: String, progress: ((Float) -> Void)? = nil) -> URL? {
        let localURL = localPathForRemote(remotePath)
        let directory = localURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let success = fileSync.pull(remotePath: remotePath, localURL: localURL, progress: progress)
        return success ? localURL : nil
    }
}
