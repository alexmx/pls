import Foundation

/// The automations in `<home>/automations`, plus every problem found while loading them.
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

    /// Ids of automations left out because of errors. An id can also be in `automations` when only a
    /// duplicate of it was left out.
    public var leftOutIDs: Set<String> {
        Set(diagnostics.filter { $0.severity == .error }.compactMap(\.automationID))
    }

    /// `$PLS_HOME`, else `$XDG_CONFIG_HOME/pls`, else `~/.config/pls`.
    public static func defaultHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        Locations.directory(xdgVariable: "XDG_CONFIG_HOME", fallback: ".config", environment: environment)
    }

    public static func load(home: URL) -> Library {
        let directory = automationsDirectory(in: home)
        var loader = Loader()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            )
        } catch {
            // A missing folder is normal before the first automation; anything else (permissions, a file
            // in its place) is a real problem. Either way, say so rather than look like an empty library.
            let missing = !FileManager.default.fileExists(atPath: directory.path)
            loader.diagnostics.append(missing
                ? Diagnostic(.warning, "folder doesn't exist; create it and add automations there", file: directory)
                : Diagnostic(.error, "can't read the folder: \(error.localizedDescription)", file: directory))
            entries = []
        }
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
            error("compiled .scpt files can't carry a header; put it in a folder with a manifest.yaml", url, id)
            return
        case "applescript": kind = .applescript
        default: kind = .shell
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            error("can't read the file as UTF-8 text", url, id)
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
        let id = folder.lastPathComponent
        let manifestURL = folder.appending(path: "manifest.yaml")
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                error("can't read manifest.yaml as UTF-8 text", manifestURL, id)
            } else {
                diagnostics.append(Diagnostic(
                    .warning, "folder has no manifest.yaml, so it's ignored", file: folder, automation: id
                ))
            }
            return
        }
        var parsed = ManifestParser.parse(text)
        guard let entryName = parsed.entry else {
            report(parsed.diagnostics, file: manifestURL, id: id)
            return
        }
        let entry = folder.appending(path: entryName)
        if !FileManager.default.fileExists(atPath: entry.path) || isDirectory(entry) {
            parsed.diagnostics.append(Diagnostic(.error, "entry file \(entryName) doesn't exist"))
        }
        let kind = parsed.kind ?? (["applescript", "scpt"].contains(entry.pathExtension) ? .applescript : .shell)
        add(
            Automation(
                id: id,
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
        report(found, file: file, id: automation.id)
        guard !found.contains(where: { $0.severity == .error }) else { return }
        seen[automation.id] = source
        automations.append(automation)
    }

    mutating func report(_ found: [Diagnostic], file: URL, id: String) {
        diagnostics += found.map { diagnostic in
            var diagnostic = diagnostic
            diagnostic.file = file
            diagnostic.automationID = id
            return diagnostic
        }
    }

    mutating func error(_ message: String, _ file: URL, _ id: String) {
        diagnostics.append(Diagnostic(.error, message, file: file, automation: id))
    }

    func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
