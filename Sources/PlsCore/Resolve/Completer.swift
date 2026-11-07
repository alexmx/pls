/// What Tab offers for `pls run` and `pls show` (SPEC §6). Each suggestion is `value` or `value:description`, the form
/// zsh's `_describe` lists; zsh itself narrows them to what's been typed of the word.
public enum Completer {
    public enum Completion: Equatable, Sendable {
        case suggestions([String])
        /// The word is a path: the shell completes it with its own file completion.
        case files
    }

    /// `pls run`'s own flags, which may sit among the values.
    private static let runFlags: Set<String> = ["-y", "--yes", "--dry-run"]

    /// The automations' ids, each described.
    public static func ids(in library: Library) -> [String] {
        library.automations.map { suggestion($0.id, $0.description ?? $0.name) }
    }

    /// Suggestions for `words[current]`, where `words` is the whole command line: `pls run [flags] <id> [values…]`.
    /// Before the id that's the ids; after it, the param names not given yet when the word starts with `-`, otherwise
    /// the options of the param the word is a value for, or files if it's a path.
    public static func runArguments(_ words: [String], current: Int, library: Library) -> Completion {
        let typed = words.prefix(current).dropFirst(2)
        guard let idIndex = typed.firstIndex(where: { !$0.hasPrefix("-") }) else {
            return .suggestions(ids(in: library))
        }
        guard let automation = library.automation(id: typed[idIndex]) else { return .suggestions([]) }
        let word = words.indices.contains(current) ? words[current] : ""
        return values(for: automation, typed: Array(typed[(idIndex + 1)...]), word: word)
    }

    /// Which value the word being typed is, by ParamBinder's own reading of the arguments before it.
    private static func values(for automation: Automation, typed: [String], word: String) -> Completion {
        // ArgumentParser takes run's own flags out of the values before ParamBinder sees them.
        let end = typed.firstIndex(of: "--") ?? typed.endIndex
        let parsed = ParamBinder.parse(typed[..<end].filter { !runFlags.contains($0) } + typed[end...], for: automation)
        if let param = parsed.awaitingValue {
            return completion(of: param)
        }
        // Positional values fill the params not named, in declared order.
        let named = Set(parsed.named.compactMap(\.param?.name))
        let open = automation.params.filter { !named.contains($0.name) }.dropFirst(parsed.positional.count)
        if !parsed.onlyPositional, word.hasPrefix("-") {
            return .suggestions(open.flatMap(flags))
        }
        return open.first.map(completion) ?? .suggestions([])
    }

    /// `--name`, plus `--no-name` for a bool; dashes stand for underscores, as on the command line.
    private static func flags(for param: Param) -> [String] {
        let name = param.name.replacingOccurrences(of: "_", with: "-")
        let description = param.description ?? param.type.description
        let flags = param.type == .bool ? ["--\(name)", "--no-\(name)"] : ["--\(name)"]
        return flags.map { suggestion($0, description) }
    }

    private static func completion(of param: Param) -> Completion {
        switch param.type {
        case let .enum(options): .suggestions(options.map { suggestion($0, nil) })
        case .bool: .suggestions(["true", "false"])
        case .path: .files
        case .string, .int, .number: .suggestions([])
        }
    }

    /// `_describe` splits a suggestion at its first unescaped colon.
    private static func suggestion(_ value: String, _ description: String?) -> String {
        let value = value.replacingOccurrences(of: ":", with: "\\:")
        guard let description, !description.isEmpty else { return value }
        return "\(value):\(description)"
    }
}
