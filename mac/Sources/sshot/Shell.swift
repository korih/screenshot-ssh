import Foundation

enum Shell {
    /// Runs a program and returns its stdout. Output goes through temp files rather than
    /// pipes: a backgrounded ssh ControlMaster can inherit a pipe and keep it open forever.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("sshot-\(UUID().uuidString)")
        let outURL = base.appendingPathExtension("out")
        let errURL = base.appendingPathExtension("err")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
        }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle
        try process.run()
        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()

        let out = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let err = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            let name = URL(fileURLWithPath: executable).lastPathComponent
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SshotError("\(name) exited \(process.terminationStatus)\(detail.isEmpty ? "" : ": \(detail)")")
        }
        return out
    }

    /// Quotes a string for a POSIX shell.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Shows a macOS notification (best effort, does not wait).
    static func notify(_ message: String) {
        let script = "display notification \(appleScriptString(message)) with title \"sshot\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

func logMessage(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}
