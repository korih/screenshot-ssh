import CryptoKit
import Foundation

/// The remote side of sshot (everything under vm/), compiled into the Mac binary.
/// `version` and `files` are generated from VERSION and vm/ by the EmbedPayload plugin.
enum Payload {
    struct File {
        let path: String
        let mode: Int
        let base64: String
    }

    /// Version written to each machine. Includes a hash of the files so that local builds
    /// with edited vm/ files still count as a different version.
    static let stamp: String = {
        var hasher = SHA256()
        for file in files {
            hasher.update(data: Data(file.path.utf8))
            hasher.update(data: Data(file.base64.utf8))
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "\(version)+\(hash.prefix(10))"
    }()

    /// A bash script that unpacks the files into a temp dir and runs vm/install.sh.
    static var installScript: String {
        var lines = [
            "set -euo pipefail",
            "tmp=$(mktemp -d)",
            "trap 'rm -rf \"$tmp\"' EXIT",
        ]
        for file in files {
            let dest = "\"$tmp\"/" + Shell.quote(file.path)
            let dir = (file.path as NSString).deletingLastPathComponent
            if !dir.isEmpty { lines.append("mkdir -p \"$tmp\"/\(Shell.quote(dir))") }
            lines.append("printf %s \(Shell.quote(file.base64)) | base64 -d > \(dest)")
            lines.append("chmod \(String(file.mode, radix: 8)) \(dest)")
        }
        lines.append("SSHOT_VERSION=\(Shell.quote(stamp)) bash \"$tmp/install.sh\"")
        return lines.joined(separator: "\n") + "\n"
    }

    static let versionPath = "~/.local/share/sshot/version"
    static let uninstallScript = """
        if [ -x ~/.local/share/sshot/uninstall.sh ]; then ~/.local/share/sshot/uninstall.sh
        else echo "sshot is not installed here"; fi
        """
}

/// Installs, checks and removes the remote side on configured machines.
enum Remote {
    /// The version installed on `host`, or nil if sshot isn't installed there.
    static func installedStamp(_ host: String) throws -> String? {
        let out = try Shell.ssh(host, "cat \(Payload.versionPath) 2>/dev/null || true")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    @discardableResult
    static func install(_ host: String) throws -> String {
        try Shell.ssh(host, "bash -s", input: Data(Payload.installScript.utf8))
    }

    @discardableResult
    static func uninstall(_ host: String) throws -> String {
        try Shell.ssh(host, "bash -s", input: Data(Payload.uninstallScript.utf8))
    }

    enum SyncResult { case current, installed(from: String?) }

    /// Installs the payload on `host` unless it already has this exact version.
    static func sync(_ host: String, force: Bool = false) throws -> SyncResult {
        let current = try installedStamp(host)
        if current == Payload.stamp && !force { return .current }
        try install(host)
        return .installed(from: current)
    }
}
