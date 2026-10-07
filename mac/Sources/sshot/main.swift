import AppKit

let usage = """
usage: sshot <command>

  init <ssh-host> [remote-dir]   write ~/.config/sshot/config.json
  send [file ...]                upload files (or the clipboard image) and print remote paths
  daemon                         run the Cmd+V interceptor in the foreground
  install                        install and start the background daemon (LaunchAgent)
  uninstall                      stop and remove the background daemon
  doctor                         check config, SSH and daemon status
"""

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sshot: \(message)\n".utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()

do {
    switch command {
    case "init":
        guard let host = args.first else { die("usage: sshot init <ssh-host> [remote-dir]") }
        var config = Config(host: host)
        if args.count > 1 { config.remoteDir = args[1] }
        try config.save()
        print("wrote \(Config.path.path)")

    case "send":
        let config = try Config.load()
        let images: [ClipImage]
        if args.isEmpty {
            images = try Clipboard.readImages()
        } else {
            images = try args.map { path -> ClipImage in
                guard FileManager.default.fileExists(atPath: path) else { throw SshotError("no such file: \(path)") }
                return .file(URL(fileURLWithPath: path))
            }
        }
        let uploader = Uploader(config: config)
        for image in images { print(try uploader.upload(image)) }

    case "daemon":
        try Daemon.run()

    case "install":
        _ = try Config.load()
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

    case "help", "-h", "--help":
        print(usage)

    default:
        die("unknown command \(command)\n\(usage)")
    }
} catch {
    die("\(error)")
}
