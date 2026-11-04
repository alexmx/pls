import Foundation

/// The automations in `<home>/automations`, plus every problem found while loading them (SPEC §2–3).
///
/// An automation with any error is left out of `automations`; its errors are in `diagnostics`.
public struct Library: Sendable {
    public let home: URL
    /// Sorted by id.
    public let automations: [Automation]
    public let diagnostics: [Diagnostic]

    public var automationsDirectory: URL {
        Self.automationsDirectory(in: home)
    }

    public func automation(id: String) -> Automation? {
        automations.first { $0.id == id }
    }

    /// `$PLS_HOME`, else `$XDG_CONFIG_HOME/pls`, else `~/.config/pls`.
    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        func directory(_ path: String) -> URL {
            URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        if let path = environment["PLS_HOME"], !path.isEmpty {
            return directory(path)
        }
        if let config = environment["XDG_CONFIG_HOME"], !config.isEmpty {
            return directory(config).appending(path: "pls", directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".config/pls",
            directoryHint: .isDirectory
        )
    }

    public static func load(home: URL) -> Library {
        let directory = automationsDirectory(in: home)
        var loader = Loader()
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )) ?? []
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            loader.load(url)
        }
        return Library(
            home: home,
            automations: loader.automations.sorted { $0.id < $1.id },
            diagnostics: loader.diagnostics
        )
    }

    private static func automationsDirectory(in home: URL) -> URL {
        home.appending(path: "automations", directoryHint: .isDirectory)
    }
}

private struct Loader {
    var automations: [Automation] = []
    var diagnostics: [Diagnostic] = []
    /// id → where it was first defined, to report duplicates.
    var seen: [String: URL] = [:]

    mutating func load(_ url: URL) {
        if isDirectory(url) {
            loadFolder(url)
        } else {
            loadFile(url)
        }
    }

    mutating func loadFile(_ url: URL) {
        let id = url.deletingPathExtension().lastPathComponent
        let kind: AutomationKind
        switch url.pathExtension {
        case "scpt":
            error("compiled .scpt files can't carry a header; put it in a folder with a manifest.yaml", url)
            return
        case "applescript": kind = .applescript
        default: kind = .shell
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            error("can't read the file as UTF-8 text", url)
            return
        }
        let parsed = HeaderParser.parse(text, commentPrefix: kind == .applescript ? "--" : "#")
        add(
            Automation(id: id, kind: kind, source: .file(url), metadata: parsed.metadata),
            diagnostics: parsed.diagnostics,
            file: url
        )
    }

    mutating func loadFolder(_ folder: URL) {
        let manifestURL = folder.appending(path: "manifest.yaml")
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            let exists = FileManager.default.fileExists(atPath: manifestURL.path)
            diagnostics.append(exists
                ? Diagnostic(.error, "can't read manifest.yaml as UTF-8 text", file: manifestURL)
                : Diagnostic(.warning, "folder has no manifest.yaml, so it's ignored", file: folder))
            return
        }
        var parsed = ManifestParser.parse(text)
        guard let entryName = parsed.entry else {
            report(parsed.diagnostics, file: manifestURL)
            return
        }
        let entry = folder.appending(path: entryName)
        if !FileManager.default.fileExists(atPath: entry.path) || isDirectory(entry) {
            parsed.diagnostics.append(Diagnostic(.error, "entry file \(entryName) doesn't exist"))
        }
        let kind = parsed.kind ?? (["applescript", "scpt"].contains(entry.pathExtension) ? .applescript : .shell)
        add(
            Automation(
                id: folder.lastPathComponent,
                kind: kind,
                source: .folder(folder, entry: entry),
                metadata: parsed.metadata
            ),
            diagnostics: parsed.diagnostics,
            file: manifestURL
        )
    }

    mutating func add(_ automation: Automation, diagnostics found: [Diagnostic], file: URL) {
        var found = found
        let source = automation.sourceURL
        if automation.id.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) == nil {
            found.append(Diagnostic(.error, "id \"\(automation.id)\" must be lowercase kebab-case, like kill-port"))
        } else if let other = seen[automation.id] {
            found.append(Diagnostic(.error, "id \(automation.id) is already used by \(other.lastPathComponent)"))
        }
        report(found, file: file)
        guard !found.contains(where: { $0.severity == .error }) else { return }
        seen[automation.id] = source
        automations.append(automation)
    }

    mutating func report(_ found: [Diagnostic], file: URL) {
        diagnostics += found.map { diagnostic in
            var diagnostic = diagnostic
            diagnostic.file = file
            return diagnostic
        }
    }

    mutating func error(_ message: String, _ file: URL) {
        diagnostics.append(Diagnostic(.error, message, file: file))
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

extension Automation {
    /// The file or folder the automation was loaded from.
    public var sourceURL: URL {
        switch source {
        case let .file(url): url
        case let .folder(url, _): url
        }
    }
}
