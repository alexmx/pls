import Foundation
@testable import PlsCore

/// A throwaway pls home in the temp directory, removed when the value is released.
final class TempHome {
    let url: URL

    init() throws {
        let raw = FileManager.default.temporaryDirectory.appending(path: "pls-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: raw.appending(path: "automations"), withIntermediateDirectories: true
        )
        // The temp dir is under /var, a symlink to /private/var; directory listings return the latter.
        // URL.resolvingSymlinksInPath() strips /private again, so use realpath.
        guard let resolved = realpath(raw.path, nil) else { throw CocoaError(.fileNoSuchFile) }
        defer { free(resolved) }
        self.url = URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `automations/<path>`, creating folders as needed.
    @discardableResult
    func write(_ path: String, _ content: String, executable: Bool = false) throws -> URL {
        let file = url.appending(path: "automations/\(path)")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
        return file
    }

    func mkdir(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: "automations/\(path)"), withIntermediateDirectories: true
        )
    }
}

/// An automation whose params are written the way a header would declare them.
func makeAutomation(_ id: String = "test", params: String...) throws -> Automation {
    var metadata = Metadata()
    for line in params {
        try metadata.add(HeaderParser.parseParam(line))
    }
    return Automation(id: id, kind: .shell, source: .file(URL(filePath: "/tmp/\(id).sh")), metadata: metadata)
}

func makeEntry(
    _ id: String,
    params: [String: String] = [:],
    chosen: [String] = [],
    via: HistoryEntry.Trigger = .run,
    exit: Int32 = 0,
    at: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> HistoryEntry {
    HistoryEntry(at: at, id: id, params: params, chosen: chosen, via: via, exit: exit, seconds: 0.123)
}
