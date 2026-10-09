import Foundation

/// Self-update: re-runs install.sh, which installs the latest release (or rebuilds from source
/// when SSHOT_REF or SSHOT_FROM_SOURCE is set), restarts the daemon and syncs every machine.
enum Upgrade {
    static let installer = "https://raw.githubusercontent.com/korih/screenshot-ssh/master/install.sh"

    static func run(force: Bool) throws -> Never {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "set -o pipefail 2>/dev/null; curl -fsSL \(Shell.quote(installer)) | sh"]
        var env = ProcessInfo.processInfo.environment
        if let bin = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            env["SSHOT_BIN_DIR"] = bin.path
        }
        if force { env["SSHOT_FORCE"] = "1" }
        process.environment = env
        try process.run()
        process.waitUntilExit()
        exit(process.terminationStatus)
    }
}
