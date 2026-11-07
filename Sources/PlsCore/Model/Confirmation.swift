/// When `pls run` and `pls again` ask before running an automation; requests always show the plan and ask.
public enum Confirmation: Sendable, Equatable {
    case never
    case always
    /// When the run's value for `param` is one of `choices`: `action=shutdown,restart` asks for those, not for cancel.
    case when(param: String, choices: [String])

    /// Whether a run with `binding`'s values asks first. A param with no value yet doesn't match any choice.
    public func asks(for binding: Binding) -> Bool {
        switch self {
        case .never: false
        case .always: true
        case let .when(param, choices): binding.values[param].map { choices.contains($0.value) } ?? false
        }
    }

    /// Why this doesn't fit `params`: it names a param they don't have, or a choice that param can't take.
    func problem(with params: [Param]) -> String? {
        guard case let .when(name, choices) = self else { return nil }
        guard let param = params.first(where: { $0.name == name }) else {
            return "confirm names param \(name), which the automation doesn't have"
        }
        for choice in choices {
            if let problem = param.type.problem(with: choice) {
                return "confirm: \(problem)"
            }
        }
        return nil
    }
}

extension Confirmation {
    /// A header's `true`, `false` or `<param>=<choice>,<choice>…`; nil for anything else.
    init?(header text: String) {
        switch text {
        case "true": self = .always
        case "false": self = .never
        default:
            guard let match = text.wholeMatch(of: /\s*([a-z][a-z0-9_]*)\s*=\s*(.+)/) else { return nil }
            let choices = match.2.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !choices.contains("") else { return nil }
            self = .when(param: String(match.1), choices: choices)
        }
    }
}
