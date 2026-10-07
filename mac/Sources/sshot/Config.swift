import Foundation

struct SshotError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Config: Codable {
    /// SSH host or alias from ~/.ssh/config.
    var host: String
    /// Directory on the VM where screenshots are stored. `~` means the remote home.
    var remoteDir = "~/.cache/sshot"
    /// Bundle IDs of apps where Cmd+V with an image on the clipboard is intercepted.
    var terminalApps = Config.defaultTerminalApps
    /// If set, only intercept when the focused window title matches this regex.
    var titleMatch: String?
    /// Images larger than this (longest edge, in pixels) are downscaled. 0 disables.
    var maxDimension = 2000

    static let defaultTerminalApps = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
    ]

    static var path: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/sshot/config.json")
    }

    enum CodingKeys: String, CodingKey {
        case host
        case remoteDir = "remote_dir"
        case terminalApps = "terminal_apps"
        case titleMatch = "title_match"
        case maxDimension = "max_dimension"
    }

    init(host: String) {
        self.host = host
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        remoteDir = try c.decodeIfPresent(String.self, forKey: .remoteDir) ?? remoteDir
        terminalApps = try c.decodeIfPresent([String].self, forKey: .terminalApps) ?? terminalApps
        titleMatch = try c.decodeIfPresent(String.self, forKey: .titleMatch)
        maxDimension = try c.decodeIfPresent(Int.self, forKey: .maxDimension) ?? maxDimension
    }

    static func load() throws -> Config {
        guard let data = try? Data(contentsOf: path) else {
            throw SshotError("no config at \(path.path); run `sshot init <ssh-host>`")
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw SshotError("invalid config \(path.path): \(error)")
        }
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: Config.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: Config.path)
    }
}
