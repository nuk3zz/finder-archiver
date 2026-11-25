import AppKit
import SwiftUI
import OSLog
import UniformTypeIdentifiers

@MainActor
@main
enum FinderArchiver {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = ArchiveModel()
    private var window: NSWindow?
    private let logger = Logger(subsystem: "com.finderarchiver.mac", category: "App")

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Finder Archiver", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Finder Archiver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem()
        main.addItem(edit)
        let editMenu = NSMenu(title: "Edit")
        edit.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
        if window == nil { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showWindow()
        guard let window else { return }
        for url in urls {
            if let (action, selection) = FinderRequest.receive(url) {
                model.enqueue(action, selection: selection, window: window)
            } else {
                logger.error("No selection was available for the incoming request")
            }
        }
    }

    private func showWindow() {
        if window == nil {
            let controller = NSHostingController(rootView: ArchiveView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Finder Archiver"
            window.setContentSize(NSSize(width: 660, height: 475))
            window.contentMinSize = NSSize(width: 560, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ArchiveModel: ObservableObject {
    @Published var selection: [URL] = []
    @Published private(set) var report = ""
    @Published private(set) var status = ""
    @Published private(set) var working = false
    @Published private(set) var failed = false
    private var pending: [(ArchiveAction, [URL], NSWindow)] = []

    func chooseFiles() {
        guard let window = NSApp.keyWindow else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.prompt = "Choose"
        picker.beginSheetModal(for: window) { response in
            if response == .OK { self.selection = picker.urls }
        }
    }

    func perform(_ action: ArchiveAction) {
        guard let window = NSApp.keyWindow else { return }
        enqueue(action, selection: selection, window: window)
    }

    func enqueue(_ action: ArchiveAction, selection: [URL], window: NSWindow) {
        guard !selection.isEmpty else { return }
        pending.append((action, selection, window))
        next()
    }

    private func next() {
        guard !working, !pending.isEmpty else { return }
        let (action, inputs, window) = pending.removeFirst()
        selection = inputs
        working = true
        failed = false
        status = action.title + "…"
        report = ""
        guard let format = action.format else {
            run(action, inputs: inputs, output: nil)
            return
        }

        let picker = NSSavePanel()
        picker.title = action.title
        picker.prompt = "Save Archive"
        picker.directoryURL = inputs[0].deletingLastPathComponent()
        let stem = inputs.count == 1 ? inputs[0].deletingPathExtension().lastPathComponent : "Archive"
        picker.nameFieldStringValue = stem + "." + format
        picker.allowedContentTypes = [UTType(filenameExtension: format) ?? .archive]
        picker.beginSheetModal(for: window) { response in
            if response == .OK, let url = picker.url {
                self.run(action, inputs: inputs, output: url)
            } else {
                self.finish(status: "Cancelled")
            }
        }
    }

    private func run(_ action: ArchiveAction, inputs: [URL], output: URL?) {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "7zz") else {
            finish(status: "7‑Zip is missing", report: "Rebuild the app to install the 7‑Zip engine.", failed: true)
            return
        }
        let engine = ArchiveEngine(executable: executable)
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try engine.run(action, on: inputs, output: output)
                }.value
                finish(status: action == .test ? "Integrity test passed" : "Completed", report: result)
            } catch {
                finish(status: "Operation failed", report: error.localizedDescription, failed: true)
            }
        }
    }

    private func finish(status: String, report: String = "", failed: Bool = false) {
        self.status = status
        self.report = report
        self.failed = failed
        working = false
        next()
    }
}

struct ArchiveView: View {
    @ObservedObject var model: ArchiveModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finder Archiver").font(.title2.bold())
                    Text("Powered by 7‑Zip").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose Files…", action: model.chooseFiles)
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(model.working)
            }
            selectionView
            HStack(spacing: 8) {
                ForEach(ArchiveAction.allCases, id: \.self) { action in
                    Button(action.title) { model.perform(action) }
                        .disabled(model.selection.isEmpty || model.working)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text("Result").font(.headline)
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
                Text(model.status).foregroundStyle(model.failed ? Color.red : Color.secondary)
            }
            ScrollView {
                Text(model.report.isEmpty ? "Results will appear here." : model.report)
                    .font(model.report.isEmpty ? .body : .system(.callout, design: .monospaced))
                    .foregroundStyle(model.report.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }

    private var selectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if model.selection.isEmpty {
                    Text("Choose files or drop them here.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.selection.enumerated()), id: \.offset) { _, url in
                        Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "doc")
                            .lineLimit(1)
                            .help(url.path)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(height: 79)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !model.working, !files.isEmpty else { return false }
            model.selection = files
            return true
        }
    }
}
