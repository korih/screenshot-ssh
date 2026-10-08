import AppKit
import ApplicationServices

/// Intercepts Cmd+V in terminal apps when the clipboard holds an image: uploads the image
/// to a remote machine, then pastes the remote path instead.
final class PasteInterceptor {
    let config: Config
    private let uploaders: [String: Uploader]
    private let titleRegex: NSRegularExpression?
    private let machineRegexes: [(regex: NSRegularExpression, host: String)]
    private let uploadQueue = DispatchQueue(label: "sshot.upload")
    private var tap: CFMachPort?
    private var busy = false

    init(config: Config) throws {
        self.config = config
        guard !config.machines.isEmpty else {
            throw SshotError("no machines configured; run `sshot machine add <ssh-host>`")
        }
        uploaders = Dictionary(uniqueKeysWithValues: config.machines.map {
            ($0.host, Uploader(machine: $0, maxDimension: config.maxDimension))
        })
        titleRegex = try PasteInterceptor.regex(config.titleMatch)
        machineRegexes = try config.machines.compactMap { m in
            try PasteInterceptor.regex(m.titleMatch).map { ($0, m.host) }
        }
    }

    private static func regex(_ pattern: String?) throws -> NSRegularExpression? {
        guard let pattern, !pattern.isEmpty else { return nil }
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw SshotError("invalid title_match regex \(pattern.debugDescription): \(error)")
        }
    }

    func start() throws {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<PasteInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw SshotError("could not create event tap; grant sshot Accessibility access in System Settings > Privacy & Security")
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Bring every machine to this version and open the shared SSH connections now,
        // so the first paste is fast.
        uploadQueue.async { [uploaders] in
            for (host, uploader) in uploaders.sorted(by: { $0.key < $1.key }) {
                do {
                    switch try Remote.sync(host) {
                    case .current: break
                    case .installed(let from): logMessage("\(host): updated sshot \(from ?? "(none)") -> \(Payload.stamp)")
                    }
                    logMessage("\(host): remote dir \(try uploader.remoteDir())")
                } catch {
                    logMessage("warning: could not reach \(host): \(error)")
                }
            }
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, let uploader = target(for: event) else {
            return Unmanaged.passUnretained(event)
        }
        // Swallow repeat presses while an upload is in flight.
        if busy { return nil }
        busy = true
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        DispatchQueue.main.async { self.uploadAndPaste(with: uploader, keyCode: keyCode) }
        return nil
    }

    /// The uploader to use if this event is an image paste we should take over, else nil.
    private func target(for event: CGEvent) -> Uploader? {
        guard event.getIntegerValueField(.eventSourceUserData) != Clipboard.syntheticMarker,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        else { return nil }

        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        guard modifiers == .maskCommand,
              NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased() == "v"
        else { return nil }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              config.terminalApps.contains(bundleID),
              Clipboard.hasImage()
        else { return nil }

        // A machine whose title_match matches wins; otherwise the default machine, unless the
        // global title_match is set and doesn't match either.
        var host = config.defaultMachine?.host
        if titleRegex != nil || !machineRegexes.isEmpty {
            let title = PasteInterceptor.focusedWindowTitle(pid: app.processIdentifier) ?? ""
            let range = NSRange(title.startIndex..., in: title)
            func matches(_ r: NSRegularExpression) -> Bool { r.firstMatch(in: title, range: range) != nil }
            if let hit = machineRegexes.first(where: { matches($0.regex) }) {
                host = hit.host
            } else if let titleRegex, !matches(titleRegex) {
                return nil
            }
        }
        return host.flatMap { uploaders[$0] }
    }

    private func uploadAndPaste(with uploader: Uploader, keyCode: CGKeyCode) {
        let images: [ClipImage]
        do {
            images = try Clipboard.readImages()
        } catch {
            fail(error)
            return
        }
        uploadQueue.async {
            do {
                let paths = try images.map { try uploader.upload($0) }
                logMessage("uploaded \(paths.joined(separator: " "))")
                DispatchQueue.main.async { self.paste(paths.joined(separator: " "), keyCode: keyCode) }
            } catch {
                DispatchQueue.main.async { self.fail(error) }
            }
        }
    }

    /// Puts `text` on the clipboard, sends Cmd+V to the terminal, then restores the image.
    private func paste(_ text: String, keyCode: CGKeyCode) {
        let pb = NSPasteboard.general
        let saved = Clipboard.snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let ourChange = pb.changeCount
        Clipboard.postPaste(keyCode: keyCode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Leave the clipboard alone if something else changed it in the meantime.
            if pb.changeCount == ourChange { Clipboard.restore(saved, to: pb) }
            self.busy = false
        }
    }

    private func fail(_ error: Error) {
        logMessage("error: \(error)")
        NSSound.beep()
        Shell.notify("Upload failed: \(error)")
        busy = false
    }

    static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window
        else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }
}

enum Daemon {
    private static var interceptor: PasteInterceptor?
    private static var permissionTimer: Timer?

    static func run() throws -> Never {
        let config = try Config.load()
        let interceptor = try PasteInterceptor(config: config)
        self.interceptor = interceptor

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let hosts = config.machines.map(\.host).joined(separator: ",")
        logMessage("sshot \(Payload.stamp) daemon starting (machines \(hosts), default \(config.defaultMachine?.host ?? "-"), apps \(config.terminalApps.joined(separator: ",")))")

        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            try interceptor.start()
            logMessage("listening for Cmd+V")
        } else {
            // Exiting would make launchd restart us in a loop; wait for the grant instead.
            logMessage("waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
            Shell.notify("Grant sshot Accessibility access in System Settings to enable image paste.")
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                do {
                    try interceptor.start()
                    logMessage("Accessibility granted; listening for Cmd+V")
                } catch {
                    logMessage("error: \(error)")
                    exit(1)
                }
            }
        }
        app.run()
        exit(0)
    }
}
