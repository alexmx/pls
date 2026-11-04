import Foundation

/// Reads the `@pls.` comment header at the top of a single-file automation (SPEC §3.1, §4.2).
///
/// The header is the run of comment and blank lines after an optional shebang; parsing stops at the first
/// line of code. Diagnostics carry 1-based line numbers but no file; the caller adds that.
public enum HeaderParser {
    public struct Result: Sendable, Equatable {
        public var metadata = Metadata()
        public var diagnostics: [Diagnostic] = []
    }

    public static func parse(_ text: String, commentPrefix: String) -> Result {
        var result = Result()
        var sawName = false, sawDescription = false
        // isNewline, not "\n": in Swift "\r\n" is a single Character, so CRLF files would never split.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if index == 0, line.hasPrefix("#!") {
                continue
            }
            if line.isEmpty {
                continue
            }
            guard line.hasPrefix(commentPrefix) else { break }
            let comment = line.dropFirst(commentPrefix.count).trimmingCharacters(in: .whitespaces)
            guard comment.hasPrefix("@pls.") else { continue }

            let lineNumber = index + 1
            func report(_ severity: Diagnostic.Severity, _ message: String) {
                result.diagnostics.append(Diagnostic(severity, message, line: lineNumber))
            }
            let entry = comment.dropFirst("@pls.".count)
            let key = String(entry.prefix { $0.isLetter || $0 == "_" })
            let rest = entry.dropFirst(key.count)

            if key == "param" {
                do {
                    let param = try parseParam(rest.trimmingCharacters(in: .whitespaces))
                    if result.metadata.params.contains(where: { $0.name == param.name }) {
                        report(.error, "param \"\(param.name)\" is declared twice")
                    } else {
                        result.metadata.params.append(param)
                    }
                } catch {
                    report(.error, error.description)
                }
                continue
            }

            guard rest.first == ":" else {
                report(.error, "expected \"@pls.\(key): <value>\"")
                continue
            }
            let value = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else {
                report(.error, "@pls.\(key) has no value")
                continue
            }
            switch key {
            case "name":
                if sawName {
                    report(.warning, "@pls.name is set twice; the last one wins")
                }
                sawName = true
                result.metadata.name = value
            case "description":
                if sawDescription {
                    report(.warning, "@pls.description is set twice; the last one wins")
                }
                sawDescription = true
                result.metadata.description = value
            case "example":
                result.metadata.examples.append(value)
            case "confirm":
                guard let flag = Bool(value) else {
                    report(.error, "@pls.confirm must be true or false")
                    continue
                }
                result.metadata.confirm = flag
            default:
                report(.warning, "unknown key @pls.\(key)")
            }
        }
        return result
    }

    /// `<name>: <type>[?] [= <default>] [-- <description>]`; the description separator needs a space on both sides.
    static func parseParam(_ text: String) throws(ParamError) -> Param {
        guard let colon = text.firstIndex(of: ":") else {
            throw ParamError("expected \"@pls.param <name>: <type>\"")
        }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        var rest = Substring(text[text.index(after: colon)...])

        var description: String?
        if let separator = rest.range(of: " -- ") {
            let text = rest[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            description = text.isEmpty ? nil : text
            rest = rest[..<separator.lowerBound]
        }

        var defaultValue: String?
        if let equals = rest.firstIndex(of: "=") {
            defaultValue = unquote(rest[rest.index(after: equals)...].trimmingCharacters(in: .whitespaces))
            rest = rest[..<equals]
        }

        var typeSpec = rest.trimmingCharacters(in: .whitespaces)
        let isOptional = typeSpec.hasSuffix("?")
        if isOptional {
            typeSpec.removeLast()
        }

        let requirement: Param.Requirement
        switch (isOptional, defaultValue) {
        case (true, .some): throw ParamError("param \(name) is optional (?) and also has a default; use one")
        case (true, .none): requirement = .optional
        case let (false, .some(value)): requirement = .defaultValue(value)
        case (false, .none): requirement = .required
        }
        return try Param(name: name, type: parseType(typeSpec), requirement: requirement, description: description)
    }

    /// `string`, `path`, `bool`, `int`, `int(1...100)`, `number(0...1)`, `enum(a|b|c)`.
    static func parseType(_ spec: String) throws(ParamError) -> ParamType {
        guard let match = spec.wholeMatch(of: /([a-z]+)(?:\((.*)\))?/) else {
            throw ParamError(spec.isEmpty ? "missing param type" : "can't read type \"\(spec)\"")
        }
        let base = String(match.1)
        let argument = match.2.map { $0.trimmingCharacters(in: .whitespaces) }

        switch base {
        case "string", "path", "bool":
            guard argument == nil else { throw ParamError("\(base) doesn't take arguments") }
            return base == "string" ? .string : base == "path" ? .path : .bool
        case "int":
            guard let argument else { return .int(nil) }
            guard let (lo, hi) = splitRange(argument), let min = Int(lo), let max = Int(hi), min <= max else {
                throw ParamError("int range must look like int(1...100)")
            }
            return .int(min...max)
        case "number":
            guard let argument else { return .number(nil) }
            guard let (lo, hi) = splitRange(argument), let min = Double(lo), let max = Double(hi), min <= max else {
                throw ParamError("number range must look like number(0...1)")
            }
            return .number(min...max)
        case "enum":
            let options = (argument ?? "").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !options.isEmpty, !options.contains(""), Set(options).count == options.count else {
                throw ParamError("enum needs distinct options, like enum(png|jpg)")
            }
            return .enum(options)
        default:
            throw ParamError("unknown type \"\(base)\"; use string, path, int, number, bool or enum")
        }
    }

    private static func splitRange(_ text: String) -> (Substring, Substring)? {
        guard let dots = text.range(of: "...") else { return nil }
        return (
            text[..<dots.lowerBound].trimmingCharacters(in: .whitespaces)[...],
            text[dots.upperBound...].trimmingCharacters(in: .whitespaces)[...]
        )
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }
}
