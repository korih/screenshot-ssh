import Foundation

struct SshotError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// A remote machine that receives screenshots.
struct Machine: Codable, Equatable {
    /// SSH host or alias from ~/.ssh/config.
    var host: String
    /// Directory on the machine where screenshots are stored. `~` means the remote home.
    var remoteDir = "~/.cache/sshot"
    /// If set, Cmd+V goes to this machine when the focused window title matches this regex.
    var titleMatch: String?

    enum CodingKeys: String, CodingKey {
        case host
        case remoteDir = "remote_dir"
        case titleMatch = "title_match"
    }

    init(host: String) {
        self.host = host
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        remoteDir = try c.decodeIfPresent(String.self, forKey: .remoteDir) ?? remoteDir
        titleMatch = try c.decodeIfPresent(String.self, forKey: .titleMatch)
    }
}

struct Config: Codable {
    var machines: [Machine] = []
    /// Host that Cmd+V uploads to when no machine's `title_match` matches.
    var defaultHost: String?
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
        case machines
        case defaultHost = "default"
        case terminalApps = "terminal_apps"
        case titleMatch = "title_match"
        case maxDimension = "max_dimension"
        // Pre-0.2 single-machine config.
        case host
        case remoteDir = "remote_dir"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machines = try c.decodeIfPresent([Machine].self, forKey: .machines) ?? []
        defaultHost = try c.decodeIfPresent(String.self, forKey: .defaultHost)
        terminalApps = try c.decodeIfPresent([String].self, forKey: .terminalApps) ?? terminalApps
        titleMatch = try c.decodeIfPresent(String.self, forKey: .titleMatch)
        maxDimension = try c.decodeIfPresent(Int.self, forKey: .maxDimension) ?? maxDimension
        if let host = try c.decodeIfPresent(String.self, forKey: .host), machine(host) == nil {
            var legacy = Machine(host: host)
            legacy.remoteDir = try c.decodeIfPresent(String.self, forKey: .remoteDir) ?? legacy.remoteDir
            machines.append(legacy)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(machines, forKey: .machines)
        try c.encodeIfPresent(defaultHost, forKey: .defaultHost)
        try c.encode(terminalApps, forKey: .terminalApps)
        try c.encodeIfPresent(titleMatch, forKey: .titleMatch)
        try c.encode(maxDimension, forKey: .maxDimension)
    }

    func machine(_ host: String) -> Machine? {
        machines.first { $0.host == host }
    }

    /// The machine used when nothing more specific applies.
    var defaultMachine: Machine? {
        defaultHost.flatMap(machine) ?? machines.first
    }

    /// Returns the machine named `host`, or the default machine when `host` is nil.
    func resolve(_ host: String?) throws -> Machine {
        if let host {
            guard let m = machine(host) else { throw SshotError("unknown machine \(host); see `sshot machine list`") }
            return m
        }
        guard let m = defaultMachine else { throw SshotError("no machines configured; run `sshot machine add <ssh-host>`") }
        return m
    }

    /// Loads the config, or returns an empty one if there is none yet.
    static func loadOrEmpty() throws -> Config {
        FileManager.default.fileExists(atPath: path.path) ? try load() : Config()
    }

    static func load() throws -> Config {
        guard let data = try? Data(contentsOf: path) else {
            throw SshotError("no config at \(path.path); run `sshot machine add <ssh-host>`")
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
