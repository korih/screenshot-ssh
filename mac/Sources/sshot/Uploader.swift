import Foundation

final class Uploader {
    let machine: Machine
    let maxDimension: Int
    private var resolvedDir: String?
    private let lock = NSLock()

    init(machine: Machine, maxDimension: Int) {
        self.machine = machine
        self.maxDimension = maxDimension
    }

    var sshOptions: [String] { Uploader.sshOptions }

    /// Shared connection options: reuse one SSH connection so uploads after the first are fast.
    static var sshOptions: [String] {
        let controlPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/sshot-%C").path
        return [
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=30m",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            // A host's RemoteCommand (e.g. auto-attach tmux) conflicts with our commands.
            "-o", "RemoteCommand=none",
            "-o", "RequestTTY=no",
        ]
    }

    /// Creates the remote directory if needed and returns its absolute path.
    func remoteDir() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if let dir = resolvedDir { return dir }

        let dir = machine.remoteDir
        let expr: String
        if dir == "~" {
            expr = "\"$HOME\""
        } else if dir.hasPrefix("~/") {
            expr = "\"$HOME\"/" + Shell.quote(String(dir.dropFirst(2)))
        } else {
            expr = Shell.quote(dir)
        }
        let out = try Shell.ssh(machine.host, "mkdir -p \(expr) && cd \(expr) && pwd -P")
        guard let resolved = out.split(separator: "\n").last.map(String.init), resolved.hasPrefix("/") else {
            throw SshotError("could not resolve remote dir \(dir) on \(machine.host) (got \(out.debugDescription))")
        }
        resolvedDir = resolved
        return resolved
    }

    /// Uploads an image and returns its absolute path on the remote host.
    func upload(_ image: ClipImage) throws -> String {
        let (data, ext) = try image.prepared(maxDimension: maxDimension)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sshot-\(UUID().uuidString).\(ext)")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dir = try remoteDir()
        let remote = "\(dir)/\(Uploader.fileName(ext: ext))"
        do {
            try Shell.run("/usr/bin/scp", sshOptions + ["-q", tmp.path, "\(machine.host):\(remote)"])
        } catch {
            // The remote dir may have been removed; resolve it again next time.
            lock.lock()
            resolvedDir = nil
            lock.unlock()
            throw error
        }
        return remote
    }

    static func fileName(ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let suffix = UUID().uuidString.prefix(4).lowercased()
        return "\(formatter.string(from: Date()))-\(suffix).\(ext)"
    }
}
