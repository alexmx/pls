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

    func run() {
        let entries = HistoryStore(file: HistoryStore.defaultFile()).recent(count)
        guard !entries.isEmpty else {
            print("No runs yet.")
            return
        }
        let rows = entries.map { entry in
            [
                Self.time(entry.at),
                entry.id + (entry.via == .again ? " (again)" : ""),
                entry.chosen.map { "\($0)=\(Self.display(entry.params[$0] ?? ""))" }.joined(separator: " "),
                entry.exit == 0 ? "ok" : "exit \(entry.exit)",
                Self.duration(entry.seconds)
            ]
        }
        let widths = (0..<4).map { column in rows.map { $0[column].count }.max() ?? 0 }
        for row in rows {
            let line = (0..<4).map { row[$0].padded(to: widths[$0]) } + [row[4]]
            print(line.joined(separator: "  "))
        }
    }

    /// "14:05" today, "Nov 3 14:05" before.
    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
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
