/// A param's final value and where it came from (shown by `--dry-run` and, later, the review step).
public struct BoundValue: Sendable, Equatable {
    /// The raw value is the label the plan display shows.
    public enum Source: String, Sendable, Equatable {
        case defaultValue = "default"
        /// On the command line.
        case given
        /// Typed at a prompt.
        case prompted = "entered"
        /// Chosen in the run `pls again` repeats.
        case repeated = "last run"
    }

    public let value: String
    public let source: Source

    public init(_ value: String, _ source: Source) {
        self.value = value
        self.source = source
    }
}

/// The values for one run of an automation. Built by `ParamBinder.bind`; prompts fill in `missing` via `supply`.
public struct Binding: Sendable, Equatable {
    public let automation: Automation
    /// Params that have a value; optional params left empty are absent.
    public private(set) var values: [String: BoundValue]

    /// Required params that still have no value, in declared order.
    public var missing: [Param] {
        automation.params.filter { $0.requirement == .required && values[$0.name] == nil }
    }

    /// Sets a value after checking it against the param's type.
    public mutating func supply(_ value: String, for param: Param, source: BoundValue.Source) throws(BindingError) {
        if let problem = param.type.problem(with: value) {
            throw BindingError("\(param.name): \(problem)")
        }
        values[param.name] = BoundValue(value, source)
    }
}

public struct BindingError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Turns the arguments after `pls run <id>` into a `Binding` (SPEC §4.3, §6).
///
/// - Positional values fill the params not given by name, in declared order.
/// - `--name value` and `--name=value`; dashes in the name may stand for underscores (`--older-than-days`).
/// - Bool params also take `--name` / `--no-name`.
/// - A lone `--` makes everything after it positional, e.g. for values that start with `--`.
public enum ParamBinder {
    public static func bind(_ automation: Automation, arguments: [String]) throws(BindingError) -> Binding {
        var named: [String: String] = [:]
        var positional: [String] = []
        var remaining = arguments[...]

        while let argument = remaining.popFirst() {
            if argument == "--" {
                positional += remaining
                break
            }
            guard argument.hasPrefix("--"), argument.count > 2 else {
                positional.append(argument)
                continue
            }
            var name = String(argument.dropFirst(2))
            var value: String?
            if let equals = name.firstIndex(of: "=") {
                value = String(name[name.index(after: equals)...])
                name = String(name[..<equals])
            }
            let (param, negated) = try lookup(name, in: automation)
            if negated {
                guard value == nil else { throw BindingError("--\(name) doesn't take a value") }
                value = "false"
            } else if value == nil {
                if param.type == .bool {
                    value = "true"
                } else {
                    guard let next = remaining.popFirst() else {
                        throw BindingError("--\(name) needs a value")
                    }
                    value = next
                }
            }
            guard named[param.name] == nil else { throw BindingError("\(param.name) is given twice") }
            named[param.name] = value
        }

        let unnamed = automation.params.filter { named[$0.name] == nil }
        guard positional.count <= unnamed.count else {
            throw BindingError(tooManyValues(automation, given: positional.count, unnamed: unnamed.count))
        }
        for (param, value) in zip(unnamed, positional) {
            named[param.name] = value
        }

        var binding = Binding(automation: automation, values: [:])
        for param in automation.params {
            if let value = named[param.name] {
                try binding.supply(value, for: param, source: .given)
            } else if case let .defaultValue(value) = param.requirement {
                try binding.supply(value, for: param, source: .defaultValue)
            }
        }
        return binding
    }

    /// A binding that repeats a run's chosen values against the automation as it is now (SPEC §8): they're replayed,
    /// defaults come from the current automation, params it no longer has are dropped, and required params it has
    /// gained are left missing for the caller to ask for.
    public static func replay(_ chosen: [String: String], for automation: Automation) throws(BindingError) -> Binding {
        var binding = try bind(automation, arguments: [])
        for param in automation.params {
            guard let value = chosen[param.name] else { continue }
            try binding.supply(value, for: param, source: .repeated)
        }
        return binding
    }

    /// The param for `--<name>` or, for bools, `--no-<name>`.
    private static func lookup(_ name: String, in automation: Automation) throws(BindingError) -> (Param, Bool) {
        let normalized = name.replacingOccurrences(of: "-", with: "_")
        if let param = automation.params.first(where: { $0.name == normalized }) {
            return (param, false)
        }
        if normalized.hasPrefix("no_"),
           let param = automation.params.first(where: { $0.name == normalized.dropFirst(3) && $0.type == .bool }) {
            return (param, true)
        }
        let known = automation.params.map { "--\($0.name)" }.joined(separator: ", ")
        throw BindingError(
            "\(automation.id) has no param --\(name)" + (known.isEmpty ? "; it takes none" : "; it takes \(known)")
        )
    }

    private static func tooManyValues(_ automation: Automation, given: Int, unnamed: Int) -> String {
        let total = automation.params.count
        if total == 0 {
            return "\(automation.id) takes no params, but \(given) value\(given == 1 ? " was" : "s were") given"
        }
        return "too many values: \(automation.id) takes \(total) param\(total == 1 ? "" : "s")"
            + (unnamed < total ? " and \(total - unnamed) \(total - unnamed == 1 ? "was" : "were") given by name" : "")
    }
}
