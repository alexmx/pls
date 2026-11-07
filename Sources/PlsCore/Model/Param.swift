/// One input an automation takes. Built only through the initializers here, which hold every rule the
/// header and manifest formats share; each parser only pulls the raw parts out of its own syntax.
public struct Param: Sendable, Equatable {
    public enum Requirement: Sendable, Equatable {
        case required
        /// May be left empty; there's no default.
        case optional
        case defaultValue(String)
    }

    /// CLI flags (`--yes`, `--dry-run`, `--help`) and names whose `PLS_<NAME>` variable pls sets itself or reads as a
    /// setting (`PLS_HOME`, `PLS_MODEL`).
    public static let reservedNames: Set<String> = [
        "yes", "dry_run", "help", "id", "home", "model", "automation_dir", "preview"
    ]

    public let name: String
    public let type: ParamType
    public let requirement: Requirement
    public let description: String?

    public init(name: String, type: ParamType, requirement: Requirement, description: String?) throws(ParamError) {
        guard name.wholeMatch(of: /[a-z][a-z0-9_]*/) != nil else {
            throw ParamError("param name \"\(name)\" must be lowercase letters, digits and _, starting with a letter")
        }
        guard !Self.reservedNames.contains(name) else {
            throw ParamError("param name \"\(name)\" is reserved")
        }
        if case let .defaultValue(value) = requirement, let problem = type.problem(with: value) {
            throw ParamError("default for \(name): \(problem)")
        }
        self.name = name
        self.type = type
        self.requirement = requirement
        self.description = description
    }
}

extension Param {
    /// The default, if the param has one.
    public var defaultValue: String? {
        if case let .defaultValue(value) = requirement {
            value
        } else {
            nil
        }
    }
}

extension Param.Requirement {
    /// Both formats mark a param optional (`?` / `optional: true`) or give a default, never both.
    init(param name: String, isOptional: Bool, defaultValue: String?) throws(ParamError) {
        switch (isOptional, defaultValue) {
        case (true, .some): throw ParamError("param \(name) is optional and also has a default; use one")
        case (true, .none): self = .optional
        case let (false, .some(value)): self = .defaultValue(value)
        case (false, .none): self = .required
        }
    }
}

public struct ParamError: Error, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum ParamType: Sendable, Equatable {
    case string
    case path
    case bool
    case int(ClosedRange<Int>?)
    case number(ClosedRange<Double>?)
    case `enum`([String])

    /// A type from its name plus the raw parts a format gives: `bounds` for an int/number range,
    /// `options` for an enum.
    init(name: String, bounds: (min: String, max: String)?, options: [String]?) throws(ParamError) {
        func noRange() throws(ParamError) {
            if bounds != nil {
                throw ParamError("\(name) doesn't take a range")
            }
        }
        func noOptions() throws(ParamError) {
            if options != nil {
                throw ParamError("\(name) doesn't take options")
            }
        }
        switch name {
        case "string", "path", "bool":
            try noRange()
            try noOptions()
            self = switch name {
            case "string": .string
            case "path": .path
            default: .bool
            }
        case "int":
            try noOptions()
            guard let bounds else {
                self = .int(nil)
                return
            }
            guard let min = Int(bounds.min), let max = Int(bounds.max), min <= max else {
                throw ParamError("int range must be whole numbers with min <= max, like 1...100")
            }
            self = .int(min...max)
        case "number":
            try noOptions()
            guard let bounds else {
                self = .number(nil)
                return
            }
            guard let min = Double(bounds.min), let max = Double(bounds.max), min <= max else {
                throw ParamError("number range must be numbers with min <= max, like 0...1")
            }
            self = .number(min...max)
        case "enum":
            try noRange()
            guard let options, !options.isEmpty, !options.contains(""), Set(options).count == options.count else {
                throw ParamError("enum needs distinct, non-empty options")
            }
            self = .enum(options)
        default:
            throw ParamError("unknown type \"\(name)\"; use string, path, int, number, bool or enum")
        }
    }

    /// Why `value` isn't valid for this type, or nil if it is.
    public func problem(with value: String) -> String? {
        switch self {
        case .string, .path:
            return nil
        case .bool:
            return value == "true" || value == "false" ? nil : "\"\(value)\" is not true or false"
        case let .int(range):
            guard let n = Int(value) else { return "\"\(value)\" is not a whole number" }
            if let range, !range.contains(n) {
                return "\(n) is outside \(range.lowerBound)...\(range.upperBound)"
            }
            return nil
        case let .number(range):
            guard let n = Double(value) else { return "\"\(value)\" is not a number" }
            if let range, !range.contains(n) {
                return "\(value) is outside \(Self.format(range.lowerBound))...\(Self.format(range.upperBound))"
            }
            return nil
        case let .enum(options):
            return options.contains(value) ? nil : "\"\(value)\" is not one of \(options.joined(separator: ", "))"
        }
    }

    /// 1.0 → "1", 0.5 → "0.5".
    fileprivate static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

extension ParamType: CustomStringConvertible {
    /// The header syntax: `int(1...100)`, `enum(png|jpg)`, `path`.
    public var description: String {
        switch self {
        case .string: "string"
        case .path: "path"
        case .bool: "bool"
        case let .int(range): range.map { "int(\($0.lowerBound)...\($0.upperBound))" } ?? "int"
        case let .number(range): range.map { "number(\(Self.format($0.lowerBound))...\(Self.format($0.upperBound)))" }
            ?? "number"
        case let .enum(options): "enum(\(options.joined(separator: "|")))"
        }
    }
}

extension Metadata {
    /// Adds a param, rejecting a second one with the same name.
    mutating func add(_ param: Param) throws(ParamError) {
        guard !params.contains(where: { $0.name == param.name }) else {
            throw ParamError("param \"\(param.name)\" is declared twice")
        }
        params.append(param)
    }
}
