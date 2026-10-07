import Foundation

enum LaunchAgent {
    static let label = "com.sshot.daemon"

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var plistURL: URL { home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var logURL: URL { home.appendingPathComponent("Library/Logs/sshot.log") }
    private static var domain: String { "gui/\(getuid())" }

    /// Writes the LaunchAgent plist and (re)starts the daemon.
    static func install() throws {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
            throw SshotError("could not determine sshot's own path")
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL)

        if (try? Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])) != nil {
            Thread.sleep(forTimeInterval: 1)
        }
        try Shell.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    static func uninstall() throws {
        _ = try? Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// The "state = ..." line from launchctl, or nil if the agent isn't loaded.
    static func state() -> String? {
        guard let out = try? Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"]) else { return nil }
        return out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("state = ") }
            ?? "loaded"
    }
}

enum Doctor {
    static func run() -> Bool {
        var ok = true
        func check(_ name: String, required: Bool = true, _ body: () throws -> String) {
            do {
                print("✓ \(name): \(try body())")
            } catch {
                if required { ok = false }
                print("\(required ? "✗" : "!") \(name): \(error)")
            }
        }

        var loaded: Config?
        check("config") {
            let config = try Config.load()
            loaded = config
            return "\(Config.path.path) (host \(config.host))"
        }
        guard let config = loaded else { return false }

        let uploader = Uploader(config: config)
        check("ssh + remote dir") { try uploader.remoteDir() }
        check("VM-side sshot (optional)", required: false) {
            try Shell.run("/usr/bin/ssh", uploader.sshOptions + [config.host, "test -x ~/.local/bin/sshot"])
            return "installed"
        }
        check("launch agent") {
            guard let state = LaunchAgent.state() else { throw SshotError("not loaded; run `sshot install`") }
            return state
        }
        if let text = try? String(contentsOf: LaunchAgent.logURL, encoding: .utf8),
           let last = text.split(separator: "\n").last {
            print("  last log line: \(last)")
        }
        return ok
    }
}
