/// What Tab offers for `pls run` and `pls show` (SPEC §6). Each suggestion is `value` or `value:description`, the form
/// zsh's `_describe` lists; zsh itself narrows them to what's been typed of the word.
public enum Completer {
    /// `pls run`'s own flags, which may sit among the values.
    private static let runFlags: Set<String> = ["-y", "--yes", "--dry-run"]

    /// The automations' ids, each described.
    public static func ids(in library: Library) -> [String] {
        library.automations.map { suggestion($0.id, $0.description ?? $0.name) }
    }

    /// Suggestions for `words[current]`, where `words` is the whole command line: `pls run [flags] <id> [values…]`.
    /// Before the id that's the ids; after it, the param names not given yet when the word starts with `-`, otherwise
    /// the options of the param the word is a value for.
    public static func run(_ words: [String], current: Int, library: Library) -> [String] {
        let typed = words.prefix(current).dropFirst(2)
        guard let idIndex = typed.firstIndex(where: { !$0.hasPrefix("-") }) else {
            return ids(in: library)
        }
        guard let automation = library.automation(id: typed[idIndex]) else { return [] }
        let word = words.indices.contains(current) ? words[current] : ""
        return values(for: automation, typed: Array(typed[(idIndex + 1)...]), word: word)
    }

    /// Follows ParamBinder's rules: which params are named, and which value the word being typed fills.
    private static func values(for automation: Automation, typed: [String], word: String) -> [String] {
        var named: Set<String> = []
        var positional = 0
        var awaitingValue: Param?
        var onlyPositional = false
        for argument in typed {
            if awaitingValue != nil {
                awaitingValue = nil
            } else if onlyPositional {
                positional += 1
            } else if argument == "--" {
                onlyPositional = true
            } else if runFlags.contains(argument) {
                continue
            } else if argument.hasPrefix("--"), argument.count > 2 {
                let body = argument.dropFirst(2)
                let name = body.prefix { $0 != "=" }
                guard let (param, negated) = ParamBinder.param(named: String(name), in: automation) else { continue }
                named.insert(param.name)
                if !negated, param.type != .bool, name.count == body.count {
                    awaitingValue = param
                }
            } else {
                positional += 1
            }
        }

        if let param = awaitingValue {
            return options(of: param)
        }
        // Positional values fill the params not named, in declared order.
        let open = automation.params.filter { !named.contains($0.name) }.dropFirst(positional)
        if !onlyPositional, word.hasPrefix("-") {
            return open.flatMap(flags)
        }
        return open.first.map(options) ?? []
    }

    /// `--name`, plus `--no-name` for a bool; dashes stand for underscores, as on the command line.
    private static func flags(for param: Param) -> [String] {
        let name = param.name.replacingOccurrences(of: "_", with: "-")
        let description = param.description ?? param.type.description
        let flags = param.type == .bool ? ["--\(name)", "--no-\(name)"] : ["--\(name)"]
        return flags.map { suggestion($0, description) }
    }

    private static func options(of param: Param) -> [String] {
        switch param.type {
        case let .enum(options): options.map { suggestion($0, nil) }
        case .bool: ["true", "false"]
        default: []
        }
    }

    /// `_describe` splits a suggestion at its first unescaped colon.
    private static func suggestion(_ value: String, _ description: String?) -> String {
        let value = value.replacingOccurrences(of: ":", with: "\\:")
        guard let description, !description.isEmpty else { return value }
        return "\(value):\(description)"
    }
}
