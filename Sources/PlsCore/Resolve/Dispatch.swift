/// Whether the command line is a natural-language request or a subcommand.
public enum Dispatch {
    /// A request unless it starts with one of `commands`, `help`, or an option a request doesn't take
    /// (`--help`, `--version`, …). A request's own options, `-y`/`--yes` and `--dry-run`, may come first.
    public static func isRequest(_ arguments: [String], commands: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        if first.hasPrefix("-") {
            return ["-y", "--yes", "--dry-run"].contains(first)
        }
        return !(commands + ["help"]).contains(first)
    }
}
