import Foundation

/// The automations in `<home>/automations` and the turned-on ones of installed collections (`CollectionStore`), plus
/// every problem found while loading them.
///
/// An automation with any error is left out of `automations`; its errors are in `diagnostics`.
public struct Library: Sendable {
    public let home: URL
    /// Sorted by id.
    public let automations: [Automation]
    public let diagnostics: [Diagnostic]
    /// Short ids that several collections use (and your library doesn't): each such automation is known only by its
    /// `owner/repo/<id>`, listed here for saying so.
    public let ambiguousIDs: [String: [String]]

    public var automationsDirectory: URL {
        Self.automationsDirectory(in: home)
    }

    /// By id, or by `owner/repo/<id>` for a collection's automation.
    public func automation(id: String) -> Automation? {
        automations.first { $0.id == id } ?? automations.first { $0.qualifiedID == id }
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
        let store = CollectionStore(home: home)
        let collections = store.installed()
        var own = Loader()
        // Without a folder of your own, collections can be all there is; with neither, say where to start.
        own.loadAll(in: automationsDirectory(in: home), missing: collections.isEmpty ? .warning : nil)
        var automations = own.automations
        var diagnostics = own.diagnostics

        // Only what you approved, as it was when you approved it, loads from a collection.
        var installed: [Automation] = []
        for collection in collections {
            let loaded = Self.automations(inCollection: collection.source, store: store)
            let approved = loaded.automations.filter(collection.isApproved)
            let approvedIDs = Set(approved.map(\.id))
            diagnostics += loaded.diagnostics.filter { $0.automationID.map(approvedIDs.contains) ?? true }
            for changed in loaded.automations
                where collection.approved[changed.id] != nil && !approvedIDs.contains(changed.id) {
                diagnostics.append(Diagnostic(
                    .warning,
                    "changed since you approved it, so it's off; `pls collection review \(collection.source)` shows it",
                    file: changed.declarationURL,
                    automation: changed.id
                ))
            }
            installed += approved
        }
        // Your own automations keep their ids; a collection's keeps its short id unless your library or another
        // collection uses it too, and is then known by `owner/repo/<id>`.
        let ownIDs = Set(automations.map(\.id))
        let collectionsUsing = Dictionary(grouping: installed, by: \.id)
        var ambiguous: [String: [String]] = [:]
        for automation in installed {
            guard ownIDs.contains(automation.id) || collectionsUsing[automation.id, default: []].count > 1 else {
                automations.append(automation)
                continue
            }
            if !ownIDs.contains(automation.id) {
                ambiguous[automation.id, default: []].append(automation.qualifiedID)
            }
            automations.append(automation.with(id: automation.qualifiedID))
        }
        return Library(
            home: home,
            automations: automations.sorted { $0.id < $1.id },
            diagnostics: diagnostics,
            ambiguousIDs: ambiguous
        )
    }

    /// Every automation in a collection's clone with its short id, approved or not, and the problems loading them.
    static func automations(
        inCollection source: String, store: CollectionStore
    ) -> (automations: [Automation], diagnostics: [Diagnostic]) {
        var loader = Loader(collection: source)
        loader.loadAll(in: store.folder(of: source).appending(path: "automations"), missing: .error)
        return (loader.automations, loader.diagnostics)
    }

    /// An automation's id: its file's name without the extension, or its folder's name.
    static func id(of entry: URL) -> String {
        isDirectory(entry) ? entry.lastPathComponent : entry.deletingPathExtension().lastPathComponent
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func automationsDirectory(in home: URL) -> URL {
        home.appending(path: "automations", directoryHint: .isDirectory)
    }
}

private struct Loader {
    /// The collection being loaded, `owner/repo`; nil for your own automations.
    var collection: String?
    var automations: [Automation] = []
    var diagnostics: [Diagnostic] = []
    /// id → where it was first defined, to report duplicates.
    var seen: [String: URL] = [:]

    /// Loads every automation in `directory`. A missing folder is reported as `missing`, or not at all when nil: it's
    /// normal before your first automation, but a problem for a collection's clone.
    mutating func loadAll(in directory: URL, missing: Diagnostic.Severity?) {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            )
        } catch {
            // Anything but a missing folder (permissions, a file in its place) is a real problem. Either way, say so
            // rather than look like an empty library.
            guard !FileManager.default.fileExists(atPath: directory.path) else {
                diagnostics.append(Diagnostic(
                    .error,
                    "can't read the folder: \(error.localizedDescription)",
                    file: directory
                ))
                return
            }
            if let missing {
                diagnostics.append(Diagnostic(
                    missing,
                    collection.map { "the clone of \($0) is missing; run `pls collection add \($0)`" }
                        ?? "folder doesn't exist; create it and add automations there",
                    file: directory
                ))
            }
            return
        }
        for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            load(url)
        }
    }

    mutating func load(_ url: URL) {
        if Library.isDirectory(url) {
            loadFolder(url)
        } else {
            loadFile(url)
        }
    }

    mutating func loadFile(_ url: URL) {
        let id = Library.id(of: url)
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
            Automation(id: id, kind: kind, source: .file(url), metadata: parsed.metadata, collection: collection),
            diagnostics: parsed.diagnostics,
            file: url
        )
    }

    mutating func loadFolder(_ folder: URL) {
        let id = Library.id(of: folder)
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
        if !FileManager.default.fileExists(atPath: entry.path) || Library.isDirectory(entry) {
            parsed.diagnostics.append(Diagnostic(.error, "entry file \(entryName) doesn't exist"))
        }
        let kind = parsed.kind ?? (["applescript", "scpt"].contains(entry.pathExtension) ? .applescript : .shell)
        add(
            Automation(
                id: id,
                kind: kind,
                source: .folder(folder, entry: entry),
                metadata: parsed.metadata,
                collection: collection
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
}
