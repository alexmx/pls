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

    /// Sets the value of each param that has one in `values`, in declared order; names it has no param for are ignored.
    mutating func supply(_ values: [String: String], source: BoundValue.Source) throws(BindingError) {
        for param in automation.params {
            if let value = values[param.name] {
                try supply(value, for: param, source: source)
            }
        }
    }

    /// Changes a value while reviewing the plan. An empty value resets a param with a default and clears an
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
