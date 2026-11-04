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
            // port — TCP port number [int(1...65535)]
            let label = param.name + (param.description.map { " — \($0)" } ?? "") + " [\(param.type)]"
            while true {
                guard let answer = ask(label + ": ") else { throw Exit.cancelled }
                if answer.isEmpty {
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

    /// Shows the plan and asks "Run? [Y/n]". Returns false if the answer is no.
    static func confirm(_ binding: Binding) -> Bool {
        printPlan(binding, write: printError)
        while true {
            switch ask("  Run? [Y/n] ")?.lowercased() {
            case nil, "n", "no": return false
            case "", "y", "yes": return true
            default: continue
            }
        }
    }

    /// nil on end of input (Ctrl-D).
    private static func ask(_ question: String) -> String? {
        FileHandle.standardError.write(Data(question.utf8))
        return readLine()?.trimmingCharacters(in: .whitespaces)
    }
}
