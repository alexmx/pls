import Darwin
import Foundation

/// One run of an automation, as recorded in history (SPEC §8).
public struct HistoryEntry: Codable, Sendable, Equatable {
    public enum Trigger: String, Codable, Sendable {
        case run
        case again
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

    public init(
        at: Date, id: String, params: [String: String], chosen: [String], via: Trigger, exit: Int32, seconds: Double
    ) {
        self.at = at
        self.id = id
        self.params = params
        self.chosen = chosen.sorted()
        self.via = via
        self.exit = exit
        self.seconds = (seconds * 100).rounded() / 100
    }
}

/// History as JSON lines: one entry per line, appended as runs finish.
public struct HistoryStore: Sendable {
    public struct WriteError: Error, CustomStringConvertible {
        public let description: String
    }

    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// `$PLS_HOME/history.jsonl`, else `$XDG_STATE_HOME/pls/history.jsonl`, else `~/.local/state/pls/history.jsonl`.
    public static func defaultFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        Locations.directory(xdgVariable: "XDG_STATE_HOME", fallback: ".local/state", environment: environment)
            .appending(path: "history.jsonl")
    }

    /// Appends the entry as one line in a single write, so runs finishing at the same time don't interleave.
    public func append(_ entry: HistoryEntry) throws(WriteError) {
        var data: Data
        do {
            data = try Self.encoder.encode(entry)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw WriteError(description: "couldn't record history in \(file.path): \(error.localizedDescription)")
        }
        data.append(UInt8(ascii: "\n"))

        let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            throw WriteError(
                description: "couldn't record history in \(file.path): \(String(cString: strerror(errno)))"
            )
        }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == data.count else {
            throw WriteError(
                description: "couldn't record history in \(file.path): \(String(cString: strerror(errno)))"
            )
        }
    }

    /// Up to `limit` entries, newest first. Lines that can't be read are skipped.
    public func recent(_ limit: Int) -> [HistoryEntry] {
        guard limit > 0, let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var entries: [HistoryEntry] = []
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let entry = try? Self.decoder.decode(HistoryEntry.self, from: Data(line.utf8)) else { continue }
            entries.append(entry)
            if entries.count == limit {
                break
            }
        }
        return entries
    }

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
