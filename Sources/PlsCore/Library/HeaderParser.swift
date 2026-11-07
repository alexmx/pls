import Foundation

/// Reads the `@pls.` comment header at the top of a single-file automation.
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
                    try result.metadata.add(parseParam(rest.trimmingCharacters(in: .whitespaces)))
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
                if result.metadata.name != nil {
                    report(.warning, "@pls.name is set twice; the last one wins")
                }
                result.metadata.name = value
            case "description":
                if result.metadata.description != nil {
                    report(.warning, "@pls.description is set twice; the last one wins")
                }
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

        return try Param(
            name: name,
            type: parseType(typeSpec),
            requirement: Param.Requirement(param: name, isOptional: isOptional, defaultValue: defaultValue),
            description: description
        )
    }

    /// `string`, `path`, `bool`, `int`, `int(1...100)`, `number(0...1)`, `enum(a|b|c)`.
    static func parseType(_ spec: String) throws(ParamError) -> ParamType {
        guard let match = spec.wholeMatch(of: /([a-z]+)(?:\((.*)\))?/) else {
            throw ParamError(spec.isEmpty ? "missing param type" : "can't read type \"\(spec)\"")
        }
        let name = String(match.1)
        guard let argument = match.2.map({ $0.trimmingCharacters(in: .whitespaces) }) else {
            return try ParamType(name: name, bounds: nil, options: nil)
        }
        switch name {
        case "int", "number":
            guard let dots = argument.range(of: "...") else {
                throw ParamError("\(name) range must look like \(name)(1...100)")
            }
            let bounds = (
                min: argument[..<dots.lowerBound].trimmingCharacters(in: .whitespaces),
                max: argument[dots.upperBound...].trimmingCharacters(in: .whitespaces)
            )
            return try ParamType(name: name, bounds: bounds, options: nil)
        case "enum":
            let options = argument.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return try ParamType(name: name, bounds: nil, options: options)
        default:
            // `string(5)` and the like: hand the argument over so the shared rules reject it.
            return try ParamType(name: name, bounds: nil, options: [argument])
        }
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }
}
