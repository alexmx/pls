/// Shows values with newlines, tabs and other control characters on one line, as backslash escapes.
public enum Escaping {
    /// Whether `value` has a character that would break a line or a column.
    public static func needsEscaping(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: isControl)
    }

    /// `value` in double quotes, with `\n`, `\t`, `\r`, `\\`, `\"` and other control characters as `\xHH` / `\uHHHH`.
    public static func quoted(_ value: String) -> String {
        "\"" + escaped(value, quote: "\"") + "\""
    }

    /// The escapes that zsh's `$'…'` quoting reads back, with `quote` escaped too.
    static func escaped(_ value: String, quote: Unicode.Scalar) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case "\\", quote: result += "\\\(scalar)"
            case _ where isControl(scalar):
                let hex = String(scalar.value, radix: 16, uppercase: true)
                result += scalar.value < 0x100
                    ? "\\x" + String(repeating: "0", count: 2 - hex.count) + hex
                    : "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: true
        default: false
        }
    }
}
