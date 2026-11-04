import ArgumentParser
import Foundation
import PlsCore

struct HistoryCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Show recent runs, newest first.",
        discussion: "Values shown are the ones you gave; defaults are left out."
    )

    @Option(name: [.customShort("n"), .customLong("limit")], help: "How many runs to show.")
    var count = 20

    func validate() throws {
        guard count >= 1 else { throw ValidationError("--limit must be at least 1") }
    }

    func run() {
        let entries = HistoryStore().recent(count)
        guard !entries.isEmpty else {
            print("No runs yet.")
            return
        }
        let rows = entries.map { entry in
            [
                Self.time(entry.at),
                entry.id + (entry.via == .again ? " (again)" : ""),
                entry.chosenValues.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.display($0.value))" }
                    .joined(separator: " "),
                entry.exit == 0 ? "ok" : "exit \(entry.exit)",
                Self.duration(entry.seconds)
            ]
        }
        table(rows).forEach { print($0) }
    }

    /// The time today ("14:05" or "2:05 PM", following the system's setting), plus the day before that.
    private static func time(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        guard !Calendar.current.isDateInToday(date) else { return time }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " " + time
    }

    /// Quoted only when it has spaces, so values stay readable and still unambiguous.
    private static func display(_ value: String) -> String {
        value.isEmpty || value.contains(where: \.isWhitespace) ? "\"\(value)\"" : value
    }

    private static func duration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        return "\(minutes)m \(Int(seconds) % 60)s"
    }
}
