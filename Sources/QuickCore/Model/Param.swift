/// One input an automation takes. Built only through `init`, which enforces the rules both formats share.
public struct Param: Sendable, Equatable {
    public enum Requirement: Sendable, Equatable {
        case required
        /// May be left empty; there's no default.
        case optional
        case defaultValue(String)
    }

    public static let reservedNames: Set<String> = ["yes", "dry_run", "help"]

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

public struct ParamError: Error, Equatable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) {
        self.description = description
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
        case let .number(range): range.map { "number(\(trim($0.lowerBound))...\(trim($0.upperBound)))" } ?? "number"
        case let .enum(options): "enum(\(options.joined(separator: "|")))"
        }
    }

    /// 1.0 → "1", 0.5 → "0.5".
    private func trim(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

public enum ParamType: Sendable, Equatable {
    case string
    case path
    case bool
    case int(ClosedRange<Int>?)
    case number(ClosedRange<Double>?)
    case `enum`([String])

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
                return "\(value) is outside \(range.lowerBound)...\(range.upperBound)"
            }
            return nil
        case let .enum(options):
            return options.contains(value) ? nil : "\"\(value)\" is not one of \(options.joined(separator: ", "))"
        }
    }
}
