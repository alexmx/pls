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
            try askUntilValid(label(param)) { (answer: String) throws(BindingError) in
                let value = answer.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { throw BindingError("\(param.name): required") }
                try binding.supply(value, for: param, source: .prompted)
            }
        }
    }

    /// Shows the plan, with what `preview` says the run would do, and asks "Run? [Y/n/e]". `e` edits each value in
    /// turn, then shows both again. Returns false if the answer is no; Ctrl-D while editing cancels.
    @MainActor
    static func review(_ binding: inout Binding, preview: (Binding) async -> [String]) async throws -> Bool {
        await (planLines(binding) + preview(binding)).forEach(printError)
        while true {
            switch ask("  Run? [Y/n/e] ")?.trimmingCharacters(in: .whitespaces).lowercased() {
            case nil, "n", "no": return false
            case "", "y", "yes": return true
            case "e", "edit":
                try edit(&binding)
                await (planLines(binding) + preview(binding)).forEach(printError)
            default: continue
            }
        }
    }

    /// Asks "Which one? [1-n]" until the answer is one of them; returns its index. nil if the answer is empty; Ctrl-D
    /// cancels.
    static func choose(among count: Int) throws -> Int? {
        let range = count == 1 ? "1" : "1-\(count)"
        var choice: Int?
        try askUntilValid("Which one? [\(range)] ") { (answer: String) throws(BindingError) in
            let trimmed = answer.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            guard let number = Int(trimmed), (1...count).contains(number) else {
                throw BindingError("pick \(range), or press Enter for none")
            }
            choice = number - 1
        }
        return choice
    }

    /// Asks for every value, prefilled with the current one; an empty answer resets or clears it (`Binding.edit`).
    /// Enter on the unchanged prefill keeps the value exactly, surrounding spaces included. A value that can't be
    /// shown on one line (a newline, a tab) isn't prefilled; Enter keeps it.
    private static func edit(_ binding: inout Binding) throws {
        for param in binding.automation.params {
            let current = binding.values[param.name]?.value
            let fitsOnALine = current.map(canPrefill) ?? true
            let prefill = fitsOnALine ? current : nil
            let question = fitsOnALine ? label(param) : label(param, note: "Enter keeps the current value")
            try askUntilValid(question, prefill: prefill) { (answer: String) throws(BindingError) in
                guard answer != prefill ?? "" else { return }
                try binding.edit(answer.trimmingCharacters(in: .whitespaces), for: param)
            }
        }
    }

    /// Whether `value` can be prefilled for editing: it shows on one line, with no newline, tab or line separator.
    static func canPrefill(_ value: String) -> Bool {
        !Escaping.needsEscaping(value)
    }

    /// Asks `question` until `apply` accepts the answer, showing why it didn't. Ctrl-D cancels.
    private static func askUntilValid(
        _ question: String, prefill: String? = nil, apply: (String) throws(BindingError) -> Void
    ) throws {
        while true {
            guard let answer = ask(question, prefill: prefill) else { throw Exit.cancelled }
            do {
                try apply(answer)
                return
            } catch {
                printError("  \(error)")
            }
        }
    }

    /// Shows `status` on stderr while `body` runs and erases it afterwards, if stderr is a terminal.
    @MainActor
    static func showingStatus<T, E: Error>(
        _ status: String, _ body: () async throws(E) -> T
    ) async throws(E) -> T {
        guard isatty(STDERR_FILENO) != 0 else { return try await body() }
        FileHandle.standardError.write(Data(status.utf8))
        // Carriage return, then erase to the end of the line.
        defer { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
        return try await body()
    }

    /// `port — TCP port number [int(1...65535)]: `, with an optional `(note)` before the colon.
    private static func label(_ param: Param, note: String? = nil) -> String {
        param.name + (param.description.map { " — \($0)" } ?? "") + " [\(param.type)]"
            + (note.map { " (\($0))" } ?? "") + ": "
    }

    /// The line as typed, untrimmed; nil on end of input (Ctrl-D on an empty line).
    static func ask(_ question: String, prefill: String? = nil) -> String? {
        guard let line = pls_read_line(question, prefill) else { return nil }
        defer { free(line) }
        return String(cString: line)
    }
}
