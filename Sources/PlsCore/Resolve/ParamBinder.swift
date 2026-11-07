import Foundation

/// A param's final value and where it came from (shown in the plan by the review step and `--dry-run`).
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
        /// Read from a natural-language request by the model.
        case request = "from request"
        /// Changed while reviewing the plan.
        case edited
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
    /// The natural-language request the `.request` values were read from, if any.
    public let request: String?
    /// Whether a value was changed while reviewing the plan. Stored, not derived from the sources: clearing an
    /// optional value or resetting one to its default leaves no `.edited` value behind.
    public private(set) var isEdited = false

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

    /// Changes a value while reviewing the plan (SPEC §6). An empty value resets a param with a default and clears an
    /// optional one, but a required param can't be empty. Only an actual change counts as an edit.
    public mutating func edit(_ value: String, for param: Param) throws(BindingError) {
        let before = values[param.name]
        guard value != before?.value ?? "" else { return }
        if value.isEmpty {
            switch param.requirement {
            case .required: throw BindingError("\(param.name): required")
            case .optional: values[param.name] = nil
            case let .defaultValue(defaultValue): values[param.name] = BoundValue(defaultValue, .defaultValue)
            }
        } else {
            try supply(value, for: param, source: .edited)
        }
        if values[param.name] != before {
            isEdited = true
        }
    }
}

extension Binding {
    /// Every param that has a default, set to it. Defaults are checked when a param is made, so they always fit.
    /// `request` is the natural-language request this run is for, if any.
    public init(defaultsOf automation: Automation, request: String? = nil) {
        var values: [String: BoundValue] = [:]
        for param in automation.params {
            if let value = param.defaultValue {
                values[param.name] = BoundValue(value, .defaultValue)
            }
        }
        self.init(automation: automation, values: values, request: request)
    }
}

public struct BindingError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// The arguments after `pls run <id>`, sorted into named and positional values before any is checked.
struct ParsedArguments {
    struct Named {
        /// As typed, without the dashes and any `=value`.
        let name: String
        /// nil when the automation has no param by that name.
        let param: Param?
        /// `--no-<name>` for a bool.
        let negated: Bool
        /// From `=value` or the next argument; nil for a bare bool flag, or when the arguments ran out first.
        let value: String?
    }

    var named: [Named] = []
    var positional: [String] = []
    /// A lone `--` was seen, so everything after it is positional.
    var onlyPositional = false

    /// The param the next argument would be the value of: the last one given, still waiting for it.
    var awaitingValue: Param? {
        guard let last = named.last, let param = last.param, !last.negated, param.type != .bool, last.value == nil
        else { return nil }
        return param
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
        let parsed = parse(arguments, for: automation)
        var named: [String: String] = [:]
        for entry in parsed.named {
            guard let param = entry.param else { throw unknownParam(entry.name, in: automation) }
            let value: String
            if entry.negated {
                guard entry.value == nil else { throw BindingError("--\(entry.name) doesn't take a value") }
                value = "false"
            } else if let given = entry.value {
                value = given
            } else if param.type == .bool {
                value = "true"
            } else {
                throw BindingError("--\(entry.name) needs a value")
            }
            guard named[param.name] == nil else { throw BindingError("\(param.name) is given twice") }
            named[param.name] = value
        }

        let positional = parsed.positional
        let unnamed = automation.params.filter { named[$0.name] == nil }
        guard positional.count <= unnamed.count else {
            throw BindingError(tooManyValues(automation, given: positional.count, unnamed: unnamed.count))
        }
        for (param, value) in zip(unnamed, positional) {
            named[param.name] = value
        }

        var binding = Binding(defaultsOf: automation)
        for param in automation.params {
            if let value = named[param.name] {
                try binding.supply(value, for: param, source: .given)
            }
        }
        return binding
    }

    /// A binding from the values the model read out of a request (SPEC §7). A value that's empty or doesn't fit its
    /// param is left out, so the param falls back to its default or gets asked for; the plan shows which. A value equal
    /// to the default stays the default: the model often fills one in, and the request didn't choose it. A path that
    /// neither looks like one nor names something in `directory` ("my screenshots folder") describes a folder rather
    /// than naming it, so it's left out.
    public static func bind(
        _ automation: Automation,
        request: String,
        values: [String: String],
        in directory: URL = URL.currentDirectory()
    ) -> Binding {
        var binding = Binding(defaultsOf: automation, request: request)
        for param in automation.params {
            guard let value = values[param.name], !value.isEmpty, value != param.defaultValue,
                  param.type != .path || isPath(value, in: directory) else { continue }
            try? binding.supply(value, for: param, source: .request)
        }
        return binding
    }

    private static func isPath(_ value: String, in directory: URL) -> Bool {
        value.hasPrefix("~") || value.hasPrefix("/") || value.hasPrefix(".") || value.contains("/")
            || FileManager.default.fileExists(atPath: directory.appending(path: value).path)
    }

    /// A binding that repeats a run's chosen values against the automation as it is now (SPEC §8): they're replayed,
    /// defaults come from the current automation, params it no longer has are dropped, and required params it has
    /// gained are left missing for the caller to ask for.
    public static func replay(_ chosen: [String: String], for automation: Automation) throws(BindingError) -> Binding {
        var binding = Binding(defaultsOf: automation)
        for param in automation.params {
            guard let value = chosen[param.name] else { continue }
            try binding.supply(value, for: param, source: .repeated)
        }
        return binding
    }

    /// Sorts the arguments by the rules above without checking anything: `bind` turns what's wrong into errors, and
    /// completion reads which value the word being typed is.
    static func parse(_ arguments: [String], for automation: Automation) -> ParsedArguments {
        var parsed = ParsedArguments()
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if argument == "--" {
                parsed.onlyPositional = true
                parsed.positional += remaining
                break
            }
            guard argument.hasPrefix("--"), argument.count > 2 else {
                parsed.positional.append(argument)
                continue
            }
            let body = argument.dropFirst(2)
            let name = String(body.prefix { $0 != "=" })
            var value = name.count < body.count ? String(body.dropFirst(name.count + 1)) : nil
            let found = param(named: name, in: automation)
            if value == nil, let found, !found.negated, found.param.type != .bool {
                value = remaining.popFirst()
            }
            parsed.named.append(.init(name: name, param: found?.param, negated: found?.negated ?? false, value: value))
        }
        return parsed
    }

    /// The param for `--<name>` or, for bools, `--no-<name>` (then `negated`); `name` is without the dashes.
    static func param(named name: String, in automation: Automation) -> (param: Param, negated: Bool)? {
        let normalized = name.replacingOccurrences(of: "-", with: "_")
        if let param = automation.params.first(where: { $0.name == normalized }) {
            return (param, false)
        }
        if normalized.hasPrefix("no_"),
           let param = automation.params.first(where: { $0.name == normalized.dropFirst(3) && $0.type == .bool }) {
            return (param, true)
        }
        return nil
    }

    private static func unknownParam(_ name: String, in automation: Automation) -> BindingError {
        let known = automation.params.map { "--\($0.name)" }.joined(separator: ", ")
        return BindingError(
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
