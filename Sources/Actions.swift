import AppKit

enum ArchiveAction: String, CaseIterable, Sendable {
    case list, test, extract, zip, sevenZip

    var title: String {
        switch self {
        case .list: "List Contents"
        case .test: "Test Archive"
        case .extract: "Extract Here"
        case .zip: "Compress to ZIP"
        case .sevenZip: "Compress to 7z"
        }
    }

    var format: String? {
        switch self {
        case .zip: "zip"
        case .sevenZip: "7z"
        default: nil
        }
    }

    private static let extensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst",
        "cab", "iso", "dmg", "wim", "msi", "lzma", "ar", "deb", "rpm", "cbz", "cbr",
        "jar", "apk", "001"
    ]

    static func looksLikeArchive(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

enum FinderRequest {
    static let scheme = "finderarchiver-dispatch"
    static let pasteboardPrefix = "com.finderarchiver.selection."

    static func pasteboard(_ id: UUID) -> NSPasteboard {
        NSPasteboard(name: .init(pasteboardPrefix + id.uuidString))
    }

    static func receive(_ url: URL) -> (ArchiveAction, [URL])? {
        guard url.scheme == scheme,
              let id = url.host.flatMap(UUID.init(uuidString:)),
              let action = ArchiveAction(rawValue: String(url.path.dropFirst())) else { return nil }
        let board = pasteboard(id)
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        board.releaseGlobally()
        guard let urls, !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return nil }
        return (action, urls)
    }
}
