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
    public var confirm = false

    public init() {}
}

public struct Automation: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// A single script file with a comment header.
        case file(URL)
        /// A folder with `manifest.yaml`; `entry` is the script inside it.
        case folder(URL, entry: URL)
    }

    public let id: String
    public let kind: AutomationKind
    public let source: Source
    public let name: String
    public let description: String?
    public let params: [Param]
    public let examples: [String]
    public let confirm: Bool

    public init(id: String, kind: AutomationKind, source: Source, metadata: Metadata) {
        self.id = id
        self.kind = kind
        self.source = source
        self.name = metadata.name ?? Self.defaultName(for: id)
        self.description = metadata.description
        self.params = metadata.params
        self.examples = metadata.examples
        self.confirm = metadata.confirm
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
