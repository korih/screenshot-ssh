import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ClipImage {
    case data(Data)
    case file(URL)

    /// Returns upload-ready bytes: GIFs as-is (to keep animation), everything else as PNG,
    /// downscaled so the longest edge is at most `maxDimension`.
    func prepared(maxDimension: Int) throws -> (data: Data, ext: String) {
        switch self {
        case .file(let url):
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "gif" { return (data, "gif") }
            return (try Clipboard.png(from: data, maxDimension: maxDimension), "png")
        case .data(let data):
            return (try Clipboard.png(from: data, maxDimension: maxDimension), "png")
        }
    }
}

enum Clipboard {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]

    /// Marks events we post ourselves so the event tap lets them through.
    static let syntheticMarker: Int64 = 0x5353_484F_54

    /// Cheap check used inside the event tap. Image files copied in Finder count; image data
    /// counts only when there is no text, so pasting rich text (which often carries a
    /// rendered image too) still pastes text.
    static func hasImage(_ pb: NSPasteboard = .general) -> Bool {
        let types = pb.types ?? []
        if types.contains(.fileURL) { return !imageFileURLs(pb).isEmpty }
        if types.contains(.string) { return false }
        return types.contains(.png) || types.contains(.tiff)
    }

    static func imageFileURLs(_ pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func readImages(_ pb: NSPasteboard = .general) throws -> [ClipImage] {
        let files = imageFileURLs(pb)
        if !files.isEmpty { return files.map { .file($0) } }
        if let data = pb.data(forType: .png) { return [.data(data)] }
        if let data = pb.data(forType: .tiff) { return [.data(data)] }
        throw SshotError("clipboard has no image")
    }

    static func png(from data: Data, maxDimension: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw SshotError("unreadable image data")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0

        let image: CGImage?
        if maxDimension > 0 && max(width, height) > maxDimension {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw SshotError("could not decode image") }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw SshotError("could not create PNG encoder")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw SshotError("PNG encoding failed") }
        return out as Data
    }

    /// Deep-copies the pasteboard contents so they can be restored later.
    static func snapshot(_ pb: NSPasteboard = .general) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem], to pb: NSPasteboard = .general) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }

    /// Posts Cmd+<keyCode> (the key the user pressed for paste), marked as synthetic.
    static func postPaste(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
