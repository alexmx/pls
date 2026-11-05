import CEditLine
import Foundation
import PlsCore

/// Questions asked in the terminal. They go to stderr, so stdout carries only the script's output.
enum Prompt {
    static var isInteractive: Bool {
        isatty(STDIN_FILENO) != 0
    }

    /// Asks for each missing required value until it's valid. Ctrl-D cancels.
    static func fillMissing(_ binding: inout Binding) throws {
        for param in binding.missing {
            while true {
                guard let answer = ask(label(param)) else { throw Exit.cancelled }
                if answer.isEmpty {
                    printError("  (required)")
                    continue
                }
                do {
                    try binding.supply(answer, for: param, source: .prompted)
                    break
                } catch {
                    printError("  \(error)")
                }
            }
        }
    }

    /// Shows the plan and asks "Run? [Y/n/e]" (SPEC §6). `e` edits each value in turn, then shows the plan again.
    /// Returns false if the answer is no; Ctrl-D while editing cancels.
    static func review(_ binding: inout Binding) throws -> Bool {
        planLines(binding).forEach(printError)
        while true {
            switch ask("  Run? [Y/n/e] ")?.lowercased() {
            case nil, "n", "no": return false
            case "", "y", "yes": return true
            case "e", "edit":
                try edit(&binding)
                planLines(binding).forEach(printError)
            default: continue
            }
        }
    }

    /// Asks for every value, prefilled with the current one; an empty answer resets or clears it (`Binding.edit`).
    private static func edit(_ binding: inout Binding) throws {
        for param in binding.automation.params {
            while true {
                guard let answer = ask(label(param), prefill: binding.values[param.name]?.value) else {
                    throw Exit.cancelled
                }
                do {
                    try binding.edit(answer, for: param)
                    break
                } catch {
                    printError("  \(error)")
                }
            }
        }
    }

    /// `port — TCP port number [int(1...65535)]: `
    private static func label(_ param: Param) -> String {
        param.name + (param.description.map { " — \($0)" } ?? "") + " [\(param.type)]: "
    }

    /// nil on end of input (Ctrl-D on an empty line).
    private static func ask(_ question: String, prefill: String? = nil) -> String? {
        guard let line = pls_read_line(question, prefill) else { return nil }
        defer { free(line) }
        return String(cString: line).trimmingCharacters(in: .whitespaces)
    }
}
