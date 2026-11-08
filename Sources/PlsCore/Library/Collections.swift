import Foundation
import Subprocess
import System

/// Automations installed from GitHub repos: each repo is a shallow clone in `<home>/collections/<owner>/<repo>`, laid
/// out like a library (an `automations/` folder), and `<home>/collections.json` records which of its automations you
/// approved, by fingerprint. Nothing of a collection runs until approved, and a change turns it off again. Your own
/// automations stay in `<home>/automations`.
public struct CollectionStore: Sendable {
    /// One installed repo and what of it you approved.
    public struct Collection: Codable, Equatable, Sendable {
        /// `owner/repo`.
        public let source: String
        /// Approved automations by id, each with the fingerprint of what you approved.
        public var approved: [String: String] = [:]

        public enum State: String, Sendable {
            /// Approved as it is now.
            case on
            /// Never approved, or approval withdrawn.
            case off
            /// Approved, but its files changed since.
            case changed
        }

        /// Where `automation`, loaded with its short id, stands.
        public func state(of automation: Automation) -> State {
            guard let fingerprint = approved[automation.id] else { return .off }
            return fingerprint == Fingerprint.of(automation) ? .on : .changed
        }
    }

    /// A record as older versions wrote it too: `only` or `disabled` instead of approvals.
    private struct StoredCollection: Decodable {
        let source: String
        let approved: [String: String]?
        let only: [String]?
        let disabled: [String]?
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

    /// A collection as typed: which repo, and whether to clone it over SSH, which reaches private repos.
    public struct Address: Equatable, Sendable {
        /// `owner/repo`.
        public let source: String
        public let overSSH: Bool
    }

    public let home: URL
    /// Where repos are cloned from over HTTPS: GitHub, or a folder of local repos in tests.
    let cloneBase: String
    /// The ssh git runs for SSH addresses (tests use one that fails at once); always in batch mode, so it never asks.
    let ssh: String

    public init(home: URL = Library.defaultHome(), cloneBase: String = "https://github.com/", ssh: String = "ssh") {
        self.home = home
        self.cloneBase = cloneBase.hasSuffix("/") ? cloneBase : cloneBase + "/"
        self.ssh = ssh
    }

    /// `owner/repo` or `https://github.com/owner/repo(.git)`, or for SSH `git@github.com:owner/repo(.git)` or
    /// `ssh://git@github.com/owner/repo(.git)`; nil for anything else.
    public static func address(from argument: String) -> Address? {
        let overSSH = argument.firstMatch(of: /^(?:ssh:\/\/)?git@github\.com[:\/]/) != nil
        let path = argument.replacing(/^(?:https?:\/\/)?github\.com\//, with: "")
            .replacing(/^(?:ssh:\/\/)?git@github\.com[:\/]/, with: "")
            .replacing(/\.git$/, with: "").replacing(/\/$/, with: "")
        guard path.wholeMatch(of: /[A-Za-z0-9-]+\/[A-Za-z0-9._-]+/) != nil else { return nil }
        return Address(source: path, overSSH: overSSH)
    }

    // MARK: record

    public func installed() -> [Collection] {
        guard let data = try? Data(contentsOf: recordFile),
              let stored = try? JSONDecoder().decode([StoredCollection].self, from: data) else { return [] }
        // An older record said which ids were on; what's on now counts as approved, so nothing changes for you.
        var migrated = false
        let collections = stored.map { record in
            if let approved = record.approved {
                return Collection(source: record.source, approved: approved)
            }
            migrated = true
            let on = automations(of: record.source).filter { automation in
                record.only.map { $0.contains(automation.id) } ?? !(record.disabled ?? []).contains(automation.id)
            }
            return Collection(source: record.source, approved: Self.fingerprints(of: on))
        }
        if migrated {
            try? save(collections)
        }
        return collections.sorted { $0.source < $1.source }
    }

    /// Every automation in `source`'s clone, approved or not, by short id.
    public func automations(of source: String) -> [Automation] {
        Library.automations(inCollection: source, store: self).automations
    }

    /// `source`'s automations that aren't approved as they are now: new, or changed since you approved them.
    public func pending(of source: String) -> [Automation] {
        guard let collection = installed().first(where: { $0.source == source }) else { return [] }
        return automations(of: source).filter { collection.state(of: $0) != .on }
    }

    /// What approving `automations` as they are now records: each id with its fingerprint. Take it before showing
    /// them, so what's approved is what was shown even if the files change meanwhile.
    public static func fingerprints(of automations: [Automation]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: automations.map { ($0.id, Fingerprint.of($0)) })
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

    /// Clones `source` if it isn't installed yet, with nothing approved, and returns what's waiting for review.
    @discardableResult
    public func add(_ source: String, overSSH: Bool = false) async throws(Failure) -> [Automation] {
        let folder = folder(of: source)
        if !FileManager.default.fileExists(atPath: folder.path) {
            let url = overSSH ? "git@github.com:\(source).git" : "\(cloneBase)\(source).git"
            do {
                try await git(["clone", "--depth", "1", "--quiet", url, folder.path])
            } catch {
                removeClone(of: source)
                if overSSH {
                    throw Failure(description: """
                    couldn't get \(source) over SSH; check that your GitHub SSH key can read it (\(error.description))
                    """)
                }
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
        var collections = installed()
        if !collections.contains(where: { $0.source == source }) {
            collections.append(Collection(source: source))
            try save(collections)
        }
        return pending(of: source)
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

    /// Approves automations of `source` by id with the fingerprint you approved (`fingerprints(of:)`), so each loads
    /// until it changes.
    public func approve(_ fingerprints: [String: String], in source: String) throws(Failure) {
        try changeRecord(of: source) { $0.approved.merge(fingerprints) { $1 } }
    }

    /// Withdraws the approval of `id` in `source`, so it doesn't load until approved again.
    public func revoke(_ id: String, in source: String) throws(Failure) {
        try changeRecord(of: source) { $0.approved[id] = nil }
    }

    private func changeRecord(of source: String, _ change: (inout Collection) -> Void) throws(Failure) {
        var collections = installed()
        guard let index = collections.firstIndex(where: { $0.source == source }) else {
            throw Failure(description: "no collection \(source) is installed")
        }
        change(&collections[index])
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

    // MARK: helpers

    /// The ids in a collection's `automations/`, by the library's own rule. Hidden entries don't count.
    static func ids(in folder: URL) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder.appending(path: "automations"), includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        )) ?? []
        return entries.map(Library.id(of:)).sorted()
    }

    /// `automations/kill-port.sh` → `kill-port`; `automations/compress/run.sh` → `compress`.
    static func id(ofPath path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "automations" else { return nil }
        return parts.count == 2 ? (String(parts[1]) as NSString).deletingPathExtension : String(parts[1])
    }

    /// ssh in batch mode: a missing key, a passphrase or an unknown host fails instead of asking. Your own
    /// `GIT_SSH_COMMAND`, if set, is kept and gets the option added.
    private var sshCommand: String {
        (ProcessInfo.processInfo.environment["GIT_SSH_COMMAND"] ?? ssh) + " -o BatchMode=yes"
    }

    /// Runs git and returns its output; it never stops to ask for a login (GitHub asks one for a repo that doesn't
    /// exist) or for anything over SSH.
    @discardableResult
    private func git(_ arguments: [String]) async throws(Failure) -> String {
        let succeeded: Bool, output: String, errors: String
        do {
            let result = try await Subprocess.run(
                .name("git"),
                arguments: Arguments(arguments),
                environment: .inherit.updating(["GIT_TERMINAL_PROMPT": "0", "GIT_SSH_COMMAND": sshCommand]),
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
