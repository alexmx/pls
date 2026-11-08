import Foundation

public enum AutomationKind: String, Sendable, Equatable {
    case shell
    case applescript
}

/// What an automation's header or manifest declares. Both formats parse into this.
public struct Metadata: Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var params: [Param] = []
    public var examples: [String] = []
    public var confirm = Confirmation.never
    /// Runs detached, as a job (`JobStore`), instead of holding the terminal until it ends.
    public var background = false
    /// Supports a preview run (`PLS_PREVIEW=1`) that says what it would do and changes nothing.
    public var preview = false

    public init() {}
}

public struct Automation: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// A single script file with a comment header.
        case file(URL)
        /// A folder with `manifest.yaml`; `entry` is the script inside it.
        case folder(URL, entry: URL)
    }

    /// Unique in the library: the file or folder name, or `owner/repo/<name>` for a collection's automation whose
    /// name is also used by your own automations or another collection.
    public private(set) var id: String
    public let kind: AutomationKind
    public let source: Source
    /// The collection it was installed from, `owner/repo`; nil for your own automations.
    public let collection: String?
    /// What its header or manifest declares; the properties below read it.
    public let metadata: Metadata
    /// The declared name, or the id in words; from the id it was loaded with, before any `owner/repo/` was added.
    public let name: String

    public var description: String? {
        metadata.description
    }

    public var params: [Param] {
        metadata.params
    }

    public var examples: [String] {
        metadata.examples
    }

    public var confirm: Confirmation {
        metadata.confirm
    }

    public var background: Bool {
        metadata.background
    }

    public var preview: Bool {
        metadata.preview
    }

    public init(id: String, kind: AutomationKind, source: Source, metadata: Metadata, collection: String? = nil) {
        self.id = id
        self.kind = kind
        self.source = source
        self.collection = collection
        self.metadata = metadata
        self.name = metadata.name ?? Self.defaultName(for: id)
    }

    /// `owner/repo/<name>` for a collection's automation, which always finds it; the id for your own.
    public var qualifiedID: String {
        collection.map { "\($0)/\(name(of: id))" } ?? id
    }

    /// The name part of an id: `kill-port` from `alexmx/tools/kill-port`.
    private func name(of id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    /// The same automation known by `id`.
    func with(id: String) -> Automation {
        var copy = self
        copy.id = id
        return copy
    }

    /// Every file it's made of, sorted: its file, or each file in its folder. A symlink counts as a file, and is not
    /// followed; the `.DS_Store` and `._` files Finder leaves don't count.
    public var files: [URL] {
        guard case let .folder(folder, _) = source else { return [sourceURL] }
        let paths = (try? FileManager.default.subpathsOfDirectory(atPath: folder.path)) ?? []
        return paths.filter { path in
            let name = (path as NSString).lastPathComponent
            return name != ".DS_Store" && !name.hasPrefix("._")
        }
        .map { folder.appending(path: $0) }
        .filter { !Library.isDirectory($0) || Fingerprint.isSymlink($0) }
        .sorted { $0.path < $1.path }
    }

    /// `file`, one of `files`, as a path relative to its folder; just its name for a single-file automation.
    public func relativePath(of file: URL) -> String {
        guard case let .folder(folder, _) = source else { return file.lastPathComponent }
        return String(file.path.dropFirst(folder.path.count + 1))
    }

    /// The file or folder the automation was loaded from.
    public var sourceURL: URL {
        switch source {
        case let .file(url): url
        case let .folder(url, _): url
        }
    }

    /// Where its metadata is written: the script's header, or the folder's manifest.yaml.
    public var declarationURL: URL {
        switch source {
        case let .file(url): url
        case let .folder(url, _): url.appending(path: "manifest.yaml")
        }
    }

    /// The script that runs.
    public var script: URL {
        switch source {
        case let .file(url): url
        case let .folder(_, entry): entry
        }
    }

    /// `kill-port` → "Kill port".
    static func defaultName(for id: String) -> String {
        let words = id.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
