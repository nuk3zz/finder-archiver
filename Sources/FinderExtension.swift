import AppKit
import FinderSync
import OSLog

@objc(FinderExtension)
final class FinderExtension: FIFinderSync {
    private let logger = Logger(subsystem: "com.finderarchiver.mac", category: "Finder")

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return nil }

        let root = NSMenu()
        let parent = NSMenuItem(title: "7zip", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let archiveOnly = urls.allSatisfy(ArchiveAction.looksLikeArchive)
        if archiveOnly {
            for action in [ArchiveAction.list, .test, .extract] {
                add(action, to: submenu)
            }
            submenu.addItem(.separator())
        }
        add(.zip, to: submenu)
        add(.sevenZip, to: submenu)
        parent.submenu = submenu
        root.addItem(parent)
        return root
    }

    private func add(_ action: ArchiveAction, to menu: NSMenu) {
        let selector = switch action {
        case .list: #selector(listContents)
        case .test: #selector(testArchive)
        case .extract: #selector(extractHere)
        case .zip: #selector(compressZIP)
        case .sevenZip: #selector(compress7z)
        }
        let item = NSMenuItem(title: action.title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func listContents() { dispatch(.list) }
    @objc private func testArchive() { dispatch(.test) }
    @objc private func extractHere() { dispatch(.extract) }
    @objc private func compressZIP() { dispatch(.zip) }
    @objc private func compress7z() { dispatch(.sevenZip) }

    private func dispatch(_ action: ArchiveAction) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else {
            logger.error("Finder did not provide a file selection")
            return
        }
        let id = UUID()
        let board = FinderRequest.pasteboard(id)
        board.clearContents()
        guard board.writeObjects(urls.map { $0 as NSURL }),
              let url = URL(string: "\(FinderRequest.scheme)://\(id.uuidString)/\(action.rawValue)") else {
            logger.error("Could not share the Finder selection")
            board.releaseGlobally()
            return
        }
        let host = Bundle(for: FinderExtension.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: .init()) { _, error in
            if let error {
                self.logger.error("Could not open the app: \(error.localizedDescription, privacy: .public)")
                board.releaseGlobally()
            }
        }
    }
}
