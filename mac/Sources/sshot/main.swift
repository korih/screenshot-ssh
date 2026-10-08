import AppKit

let usage = """
usage: sshot <command>

  machine add <ssh-host> [--dir D] [--title REGEX] [--default]
                                 install sshot on a machine and send screenshots there
  machine remove <ssh-host> [--keep-remote]
                                 stop using a machine and uninstall sshot from it
  machine list                   show machines and the sshot version installed on each
  machine sync [ssh-host] [--force]
                                 bring machines up to this Mac's sshot version
  machine default <ssh-host>     machine used when no title_match picks one
  send [-m ssh-host] [file ...]  upload files (or the clipboard image) and print remote paths
  install                        install and start the background daemon (LaunchAgent)
  uninstall                      stop and remove the background daemon
  doctor                         check config, SSH, remote versions and daemon status
  upgrade [--force]              rebuild from the latest source and sync all machines
  version                        print the version
  daemon                         run the Cmd+V interceptor in the foreground
"""

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sshot: \(message)\n".utf8))
    exit(1)
}

/// Removes `--name value` from args and returns the value.
func takeOption(_ name: String, from args: inout [String]) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { die("\(name) needs a value") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

/// Removes `--name` from args and returns whether it was present.
func takeFlag(_ name: String, from args: inout [String]) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

/// Restarts the daemon so it picks up config changes; installs it if it isn't running yet.
func applyConfig(_ config: Config) throws {
    if config.machines.isEmpty {
        if LaunchAgent.state() != nil {
            try LaunchAgent.uninstall()
            print("no machines left; stopped the daemon")
        }
        return
    }
    let firstTime = LaunchAgent.state() == nil
    try LaunchAgent.install()
    if firstTime {
        print("""
        started the background daemon (log: \(LaunchAgent.logURL.path))
        When macOS asks, allow sshot in System Settings > Privacy & Security > Accessibility.
        """)
    }
}

func machineCommand(_ args: [String]) throws {
    var args = args
    let sub = args.isEmpty ? "list" : args.removeFirst()
    var config = try Config.loadOrEmpty()

    switch sub {
    case "add":
        let dir = takeOption("--dir", from: &args)
        let title = takeOption("--title", from: &args)
        let makeDefault = takeFlag("--default", from: &args)
        guard args.count == 1, let host = args.first else {
            die("usage: sshot machine add <ssh-host> [--dir D] [--title REGEX] [--default]")
        }
        print("connecting to \(host)...")
        do {
            try Shell.ssh(host, "true")
        } catch {
            throw SshotError("""
            cannot ssh to \(host) without a prompt (\(error)).
            Set up key-based login first, e.g. `ssh-copy-id \(host)`, and check `ssh \(host)` works.
            """)
        }
        print(try Remote.install(host), terminator: "")

        var machine = config.machine(host) ?? Machine(host: host)
        if let dir { machine.remoteDir = dir }
        if let title { machine.titleMatch = title.isEmpty ? nil : title }
        if let i = config.machines.firstIndex(where: { $0.host == host }) {
            config.machines[i] = machine
        } else {
            config.machines.append(machine)
        }
        if makeDefault || config.defaultHost.flatMap(config.machine) == nil { config.defaultHost = host }
        try config.save()
        print("added \(host)\(config.defaultHost == host ? " (default)" : "")")
        try applyConfig(config)

    case "remove", "rm":
        let keepRemote = takeFlag("--keep-remote", from: &args)
        guard args.count == 1, let host = args.first else {
            die("usage: sshot machine remove <ssh-host> [--keep-remote]")
        }
        guard config.machine(host) != nil else { throw SshotError("unknown machine \(host)") }
        if !keepRemote {
            do {
                print(try Remote.uninstall(host), terminator: "")
            } catch {
                print("warning: could not uninstall on \(host): \(error)")
            }
        }
        config.machines.removeAll { $0.host == host }
        if config.defaultHost == host { config.defaultHost = config.machines.first?.host }
        try config.save()
        print("removed \(host)")
        try applyConfig(config)

    case "list", "ls":
        guard !config.machines.isEmpty else {
            print("no machines; add one with `sshot machine add <ssh-host>`")
            return
        }
        print("this Mac: \(Payload.stamp)")
        for m in config.machines {
            let status: String
            do {
                switch try Remote.installedStamp(m.host) {
                case nil: status = "not installed"
                case Payload.stamp?: status = "up to date"
                case let other?: status = "out of date (\(other))"
                }
            } catch {
                status = "unreachable"
            }
            var line = "\(m.host == config.defaultMachine?.host ? "*" : " ") \(m.host)  \(m.remoteDir)  \(status)"
            if let t = m.titleMatch { line += "  title_match=\(t)" }
            print(line)
        }

    case "sync":
        let force = takeFlag("--force", from: &args)
        let hosts = args.isEmpty ? config.machines.map(\.host) : args
        guard !hosts.isEmpty else { print("no machines to sync"); return }
        var failed = false
        for host in hosts {
            guard config.machine(host) != nil else { throw SshotError("unknown machine \(host)") }
            do {
                switch try Remote.sync(host, force: force) {
                case .current: print("\(host): up to date (\(Payload.stamp))")
                case .installed(let from): print("\(host): \(from ?? "not installed") -> \(Payload.stamp)")
                }
            } catch {
                failed = true
                print("\(host): failed: \(error)")
            }
        }
        if failed { exit(1) }

    case "default":
        guard args.count == 1, let host = args.first else { die("usage: sshot machine default <ssh-host>") }
        guard config.machine(host) != nil else { throw SshotError("unknown machine \(host)") }
        config.defaultHost = host
        try config.save()
        print("default machine: \(host)")
        try applyConfig(config)

    default:
        die("unknown machine command \(sub)\n\(usage)")
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()

do {
    switch command {
    case "machine", "machines", "m":
        try machineCommand(args)

    case "send":
        let config = try Config.load()
        let machine = try config.resolve(takeOption("-m", from: &args))
        let images: [ClipImage]
        if args.isEmpty {
            images = try Clipboard.readImages()
        } else {
            images = try args.map { path -> ClipImage in
                guard FileManager.default.fileExists(atPath: path) else { throw SshotError("no such file: \(path)") }
                return .file(URL(fileURLWithPath: path))
            }
        }
        let uploader = Uploader(machine: machine, maxDimension: config.maxDimension)
        for image in images { print(try uploader.upload(image)) }

    case "daemon":
        try Daemon.run()

    case "install":
        _ = try Config.load().resolve(nil)
        try LaunchAgent.install()
        print("""
        installed \(LaunchAgent.plistURL.path)
        log: \(LaunchAgent.logURL.path)
        If prompted, allow sshot in System Settings > Privacy & Security > Accessibility.
        """)

    case "uninstall":
        try LaunchAgent.uninstall()
        print("removed \(LaunchAgent.plistURL.path)")

    case "doctor":
        exit(Doctor.run() ? 0 : 1)

    case "upgrade", "update":
        try Upgrade.run(force: takeFlag("--force", from: &args))

    case "version", "--version", "-v":
        print("sshot \(Payload.stamp)")

    case "help", "-h", "--help":
        print(usage)

    default:
        die("unknown command \(command)\n\(usage)")
    }
} catch {
    die("\(error)")
}
