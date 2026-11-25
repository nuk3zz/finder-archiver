import Foundation
import Darwin

struct ArchiveEngine: Sendable {
    let executable: URL
    private var files: FileManager { .default }

    func run(_ action: ArchiveAction, on selection: [URL], output: URL? = nil) throws -> String {
        let selection = selection.map { $0.standardizedFileURL }
        guard !selection.isEmpty else { throw EngineError("Choose at least one file or folder.") }
        if let format = action.format {
            guard let output else { throw EngineError("Choose where to save the archive.") }
            return try compress(selection, to: output, format: format)
        }
        var reports = [String]()
        var failures = 0
        for archive in selection {
            do {
                let detail = switch action {
                case .list: try invoke(["l", "--", archive.path])
                case .test: try invoke(["t", "--", archive.path])
                case .extract: try extract(archive)
                default: throw EngineError("Unsupported archive action.")
                }
                reports.append("\(archive.lastPathComponent)\n\(detail)")
            } catch {
                failures += 1
                reports.append("\(archive.lastPathComponent)\n\(error.localizedDescription)")
            }
        }
        let report = reports.joined(separator: "\n\n")
        if failures > 0 { throw EngineError(report) }
        return report
    }

    private func compress(_ inputs: [URL], to output: URL, format: String) throws -> String {
        let parent = output.deletingLastPathComponent().resolvingSymlinksInPath()
        for input in inputs {
            let source = input.resolvingSymlinksInPath()
            if (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true,
               parent.pathComponents.starts(with: source.pathComponents) {
                throw EngineError("Save the archive outside the folder being compressed.")
            }
        }

        let stage = try stagingFolder(in: parent)
        defer { try? files.removeItem(at: stage) }
        let candidate = stage.appendingPathComponent("archive.\(format)")
        var base = inputs[0].deletingLastPathComponent()
        for input in inputs.dropFirst() {
            while !input.deletingLastPathComponent().pathComponents.starts(with: base.pathComponents) {
                base.deleteLastPathComponent()
            }
        }
        let names = inputs.map {
            "./" + $0.pathComponents.dropFirst(base.pathComponents.count).joined(separator: "/")
        }
        _ = try invoke(["a", "-t\(format)", "-spd", "-sse", "-snl", "--", candidate.path] + names, in: base)
        try publish(candidate, to: output)
        return "Created \(output.path)"
    }

    private func extract(_ archive: URL) throws -> String {
        let parent = archive.deletingLastPathComponent()
        let base = archive.deletingPathExtension().lastPathComponent
        let stage = try stagingFolder(in: parent)
        defer { try? files.removeItem(at: stage) }
        _ = try invoke(["x", "-y", "-aos", "-spd", "-o\(stage.path)", "--", archive.path])
        try inheritQuarantine(from: archive, to: stage)

        // Publish a complete extraction without replacing anything at the destination.
        for number in 1...10_000 {
            let displayName = number == 1 ? base : "\(base) \(number)"
            let destination = parent.appendingPathComponent(displayName, isDirectory: true)
            do {
                try publish(stage, to: destination)
                return "Extracted to \(destination.path)"
            } catch let error as POSIXError where error.code == .EEXIST {
                continue
            }
        }
        throw EngineError("Could not find an available extraction folder name.")
    }

    private func inheritQuarantine(from source: URL, to root: URL) throws {
        let key = "com.apple.quarantine"
        let count = getxattr(source.path, key, nil, 0, 0, 0)
        guard count > 0 else { return }
        var data = Data(count: count)
        guard data.withUnsafeMutableBytes({ getxattr(source.path, key, $0.baseAddress, count, 0, 0) }) == count else {
            throw EngineError("Could not read the archive’s quarantine information.")
        }
        var walkError: Error?
        guard let children = files.enumerator(at: root, includingPropertiesForKeys: nil, errorHandler: { _, error in
            walkError = error
            return false
        }) else { throw EngineError("Could not read the extracted files.") }

        func apply(to url: URL) throws {
            let result = data.withUnsafeBytes { setxattr(url.path, key, $0.baseAddress, count, 0, XATTR_NOFOLLOW) }
            if result != 0 { throw EngineError("Could not preserve quarantine for \(url.lastPathComponent).") }
        }
        try apply(to: root)
        for case let url as URL in children {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink != true { try apply(to: url) }
        }
        if let walkError { throw walkError }
    }

    private func stagingFolder(in parent: URL) throws -> URL {
        let folder = parent.appendingPathComponent(".finder-archiver-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return folder
    }

    private func publish(_ item: URL, to destination: URL) throws {
        if renamex_np(item.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(code)
        }
    }

    private func invoke(_ args: [String], in directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = [args[0], "-bd", "-sccUTF-8"] + args.dropFirst()
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        try pipe.fileHandleForWriting.close()

        let limit = 1_048_576
        var retained = Data()
        var truncated = false
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            // Drain the pipe even when the displayed log reaches its limit.
            let space = limit - retained.count
            retained.append(contentsOf: chunk.prefix(space))
            truncated = truncated || chunk.count > space
        }

        process.waitUntilExit()
        let message = String(decoding: retained, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            + (truncated ? "\n\nOutput limited to 1 MiB." : "")
        if process.terminationReason != .exit || process.terminationStatus != 0 {
            throw EngineError("7‑Zip exited with status \(process.terminationStatus).\n\n\(message)")
        }
        return message
    }
}

struct EngineError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
