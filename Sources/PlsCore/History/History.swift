import Darwin
import Foundation

/// One run of an automation, as recorded in history (SPEC §8).
public struct HistoryEntry: Codable, Sendable, Equatable {
    public enum Trigger: String, Codable, Sendable {
        case run
        case again
        /// A natural-language request.
        case request
    }

    public let at: Date
    public let id: String
    /// Every value the run used, defaults included.
    public let params: [String: String]
    /// The params whose value was typed or entered rather than defaulted; `pls again` replays only these.
    public let chosen: [String]
    public let via: Trigger
    public let exit: Int32
    public let seconds: Double
    /// The words of a natural-language request; absent for other runs.
    public let request: String?
    /// Whether a request's plan was changed before running; absent for other runs.
    public let edited: Bool?

    public init(
        at: Date, id: String, params: [String: String], chosen: [String], via: Trigger, exit: Int32, seconds: Double,
        request: String? = nil, edited: Bool? = nil
    ) {
        self.at = at
        self.id = id
        self.params = params
        self.chosen = chosen.sorted()
        self.via = via
        self.exit = exit
        self.seconds = (seconds * 100).rounded() / 100
        self.request = request
        self.edited = edited
    }
}

extension HistoryEntry {
    /// The values that were typed, entered or repeated: what `pls again` replays.
    public var chosenValues: [String: String] {
        params.filter { chosen.contains($0.key) }
    }

    /// The entry for a finished run of `binding`.
    public init(_ binding: Binding, via trigger: Trigger, exit: Int32, seconds: Double, at: Date) {
        self.init(
            at: at,
            id: binding.automation.id,
            params: binding.values.mapValues(\.value),
            chosen: binding.values.filter { $0.value.source != .defaultValue }.map(\.key),
            via: trigger,
            exit: exit,
            seconds: seconds,
            request: trigger == .request ? binding.request : nil,
            edited: trigger == .request ? binding.isEdited : nil
        )
    }
}

/// History as JSON lines: one entry per line, appended as runs finish.
public struct HistoryStore: Sendable {
    public struct WriteError: Error, CustomStringConvertible {
        public let description: String
    }

    public let file: URL

    /// The store at `defaultFile()` unless a file is given.
    public init(file: URL = HistoryStore.defaultFile()) {
        self.file = file
    }

    /// `$PLS_HOME/history.jsonl`, else `$XDG_STATE_HOME/pls/history.jsonl`, else `~/.local/state/pls/history.jsonl`.
    public static func defaultFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        Locations.directory(xdgVariable: "XDG_STATE_HOME", fallback: ".local/state", environment: environment)
            .appending(path: "history.jsonl")
    }

    /// Appends the entry as one line in a single write, so runs finishing at the same time don't interleave.
    /// If the file doesn't end with a newline (a write cut short), the entry starts on a fresh line so it isn't
    /// glued to the broken one.
    public func append(_ entry: HistoryEntry) throws(WriteError) {
        func failure(_ reason: String) -> WriteError {
            WriteError(description: "couldn't record history in \(file.path): \(reason)")
        }
        var line: Data
        do {
            line = try Self.encoder.encode(entry)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw failure(error.localizedDescription)
        }
        line.append(Self.newline)

        let descriptor = open(file.path, O_RDWR | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw failure(String(cString: strerror(errno))) }
        defer { close(descriptor) }

        var info = stat()
        var last: UInt8 = 0
        if fstat(descriptor, &info) == 0, info.st_size > 0, pread(descriptor, &last, 1, info.st_size - 1) == 1,
           last != Self.newline {
            line.insert(Self.newline, at: 0)
        }
        let written = line.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard written == line.count else {
            throw failure(written < 0 ? String(cString: strerror(errno)) : "wrote \(written) of \(line.count) bytes")
        }
    }

    /// Up to `limit` entries, newest first. A line that can't be read is skipped, and only that line: the file is
    /// split on the newline byte alone (JSON text may contain U+2028 and friends) and decoded line by line (so stray
    /// bytes in one line don't make the whole file unreadable).
    public func recent(_ limit: Int) -> [HistoryEntry] {
        guard limit > 0, let data = try? Data(contentsOf: file) else { return [] }
        var entries: [HistoryEntry] = []
        for line in data.split(separator: Self.newline).reversed() {
            guard let entry = try? Self.decoder.decode(HistoryEntry.self, from: Data(line)) else { continue }
            entries.append(entry)
            if entries.count == limit {
                break
            }
        }
        return entries
    }

    private static let newline = UInt8(ascii: "\n")

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Why the last run can't be repeated.
public enum ReplayError: Error, Equatable {
    case noHistory
    /// The automation isn't in the library; `hasProblems` when it's there but has errors that keep it out.
    case automationGone(id: String, hasProblems: Bool)
    /// A value chosen last time doesn't fit the automation as it is now.
    case valueNoLongerFits(id: String, BindingError)
}

extension HistoryStore {
    /// A binding that repeats the newest run against `library` as it is now (SPEC §8).
    public func replayLast(in library: Library) throws(ReplayError) -> Binding {
        guard let last = recent(1).first else { throw .noHistory }
        guard let automation = library.automation(id: last.id) else {
            throw .automationGone(id: last.id, hasProblems: library.leftOutIDs.contains(last.id))
        }
        do {
            return try ParamBinder.replay(last.chosenValues, for: automation)
        } catch {
            throw .valueNoLongerFits(id: last.id, error)
        }
    }
}
