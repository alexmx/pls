import Foundation
import Subprocess
import System

/// Automations installed from GitHub repos: each repo is a shallow clone in `<home>/collections/<owner>/<repo>`, laid
/// out like a library (an `automations/` folder), and `<home>/collections.json` records which of its automations are
/// turned on. Your own automations stay in `<home>/automations`.
public struct CollectionStore: Sendable {
    /// One installed repo and which of its automations load.
    public struct Collection: Codable, Equatable, Sendable {
        /// `owner/repo`.
        public let source: String
        /// Only these ids load, when set (`--only`); otherwise all but `disabled`.
        public var only: [String]?
        public var disabled: [String] = []

        public func isEnabled(_ id: String) -> Bool {
            only.map { $0.contains(id) } ?? !disabled.contains(id)
        }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// What an update changed, by automation id.
    public struct Changes: Equatable, Sendable {
        public let source: String
        public var changed: [String] = []
        public var added: [String] = []
        public var removed: [String] = []
    }

    public let home: URL
    /// Where repos are cloned from: GitHub, or a folder of local repos in tests.
    let cloneBase: String

    public init(home: URL = Library.defaultHome(), cloneBase: String = "https://github.com/") {
        self.home = home
        self.cloneBase = cloneBase.hasSuffix("/") ? cloneBase : cloneBase + "/"
    }

    /// `owner/repo` from `owner/repo` or `https://github.com/owner/repo(.git)`; nil for anything else.
    public static func source(from argument: String) -> String? {
        let path = argument.replacing(/^(?:https?:\/\/)?github\.com\//, with: "")
            .replacing(/\.git$/, with: "").replacing(/\/$/, with: "")
        return path.wholeMatch(of: /[A-Za-z0-9-]+\/[A-Za-z0-9._-]+/) != nil ? path : nil
    }

    // MARK: record

    public func installed() -> [Collection] {
        guard let data = try? Data(contentsOf: recordFile) else { return [] }
        return ((try? JSONDecoder().decode([Collection].self, from: data)) ?? []).sorted { $0.source < $1.source }
    }

    /// The clone of `source`.
    public func folder(of source: String) -> URL {
        home.appending(path: "collections/\(source)", directoryHint: .isDirectory)
    }

    private var recordFile: URL {
        home.appending(path: "collections.json")
    }

    private func save(_ collections: [Collection]) throws(Failure) {
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(collections.sorted { $0.source < $1.source }).write(to: recordFile)
        } catch {
            throw Failure(description: "couldn't save \(recordFile.path): \(error.localizedDescription)")
        }
    }

    // MARK: changes

    /// Clones `source` if it isn't installed yet, then records the selection: `only` those ids, or all. Returns the
    /// ids of its automations.
    @discardableResult
    public func add(_ source: String, only: [String]? = nil) async throws(Failure) -> [String] {
        let folder = folder(of: source)
        if !FileManager.default.fileExists(atPath: folder.path) {
            do {
                try await git(["clone", "--depth", "1", "--quiet", "\(cloneBase)\(source).git", folder.path])
            } catch {
                removeClone(of: source)
                // GitHub asks for a login when a repo doesn't exist, so it may not even say so.
                let missing = [
                    "could not read Username",
                    "not found",
                    "does not exist",
                    "does not appear to be a git repository"
                ]
                .contains { error.description.localizedCaseInsensitiveContains($0) }
                throw missing ? Failure(description: "\(source) isn't a public GitHub repo") : error
            }
        }
        let ids = Self.ids(in: folder)
        guard !ids.isEmpty else {
            removeClone(of: source)
            throw Failure(description: "\(source) has no automations folder with automations in it")
        }
        if let unknown = only?.first(where: { !ids.contains($0) }) {
            throw Failure(description: "\(source) has no automation \(unknown); it has \(ids.joined(separator: ", "))")
        }
        var collections = installed().filter { $0.source != source }
        collections.append(Collection(source: source, only: only))
        try save(collections)
        return ids
    }

    /// Pulls each collection (all when `sources` is empty) and reports what changed among its automations.
    public func update(_ sources: [String] = []) async throws(Failure) -> [Changes] {
        var report: [Changes] = []
        for collection in installed() where sources.isEmpty || sources.contains(collection.source) {
            let folder = folder(of: collection.source)
            let before = try await git(["-C", folder.path, "rev-parse", "HEAD"])
            let idsBefore = Set(Self.ids(in: folder))
            try await git(["-C", folder.path, "pull", "--ff-only", "--quiet"])
            let after = try await git(["-C", folder.path, "rev-parse", "HEAD"])
            var changes = Changes(source: collection.source)
            if before != after {
                let idsAfter = Set(Self.ids(in: folder))
                let touched = try await git([
                    "-C",
                    folder.path,
                    "diff",
                    "--name-only",
                    before,
                    after,
                    "--",
                    "automations"
                ])
                .split(separator: "\n").compactMap { Self.id(ofPath: String($0)) }
                changes.added = idsAfter.subtracting(idsBefore).sorted()
                changes.removed = idsBefore.subtracting(idsAfter).sorted()
                changes.changed = Set(touched).intersection(idsBefore).intersection(idsAfter).sorted()
            }
            report.append(changes)
        }
        return report
    }

    /// Turns `id` of `source` on or off, keeping the choice across updates.
    public func setEnabled(_ enabled: Bool, id: String, in source: String) throws(Failure) {
        var collections = installed()
        guard let index = collections.firstIndex(where: { $0.source == source }) else {
            throw Failure(description: "no collection \(source) is installed")
        }
        guard Self.ids(in: folder(of: source)).contains(id) else {
            throw Failure(description: "\(source) has no automation \(id)")
        }
        var collection = collections[index]
        if var only = collection.only {
            only.removeAll { $0 == id }
            collection.only = enabled ? only + [id] : only
        } else {
            collection.disabled.removeAll { $0 == id }
            if !enabled {
                collection.disabled.append(id)
            }
        }
        collections[index] = collection
        try save(collections)
    }

    public func remove(_ source: String) throws(Failure) {
        let collections = installed()
        guard collections.contains(where: { $0.source == source }) else {
            throw Failure(description: "no collection \(source) is installed")
        }
        removeClone(of: source)
        try save(collections.filter { $0.source != source })
    }

    /// Deletes the clone, and the owner's folder once it's empty.
    private func removeClone(of source: String) {
        try? FileManager.default.removeItem(at: folder(of: source))
        let owner = folder(of: source).deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: owner.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: owner)
        }
    }

    /// The ids of `source`'s automations, turned on or not.
    public func automationIDs(of source: String) -> [String] {
        Self.ids(in: folder(of: source))
    }

    // MARK: helpers

    /// The ids in a collection's `automations/`, as the library loads them: file names without their extension, and
    /// folder names. Hidden entries don't count.
    static func ids(in folder: URL) -> [String] {
        let automations = folder.appending(path: "automations")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: automations.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    /// `automations/kill-port.sh` → `kill-port`; `automations/compress/run.sh` → `compress`.
    static func id(ofPath path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "automations" else { return nil }
        return parts.count == 2 ? (String(parts[1]) as NSString).deletingPathExtension : String(parts[1])
    }

    /// Runs git and returns its output; it never stops to ask for a login (GitHub asks one for a repo that doesn't
    /// exist).
    @discardableResult
    private func git(_ arguments: [String]) async throws(Failure) -> String {
        let succeeded: Bool, output: String, errors: String
        do {
            let result = try await Subprocess.run(
                .name("git"),
                arguments: Arguments(arguments),
                environment: .inherit.updating(["GIT_TERMINAL_PROMPT": "0"]),
                output: .string(limit: 1 << 20),
                error: .string(limit: 1 << 16)
            )
            (succeeded, output, errors) = (
                result.terminationStatus.isSuccess,
                result.standardOutput,
                result.standardError
            )
        } catch {
            throw Failure(
                description: "git isn't available; install Xcode's command-line tools (xcode-select --install)"
            )
        }
        guard succeeded else {
            // git's first "fatal:" line says what went wrong; what follows is general advice.
            let lines = errors.split(separator: "\n").map(String.init)
            let message = lines.first { $0.hasPrefix(
                "fatal: "
            ) }.map { String($0.dropFirst(7)) } ?? lines.last ?? "failed"
            let command = arguments.first == "-C" ? arguments.dropFirst(2).first : arguments.first
            throw Failure(description: "git \(command ?? ""): \(message)")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
