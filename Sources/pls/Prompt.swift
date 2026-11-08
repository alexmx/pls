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

    /// Shows the plan, with what `preview` says the run would do, and asks "Run?", answered with one key: Enter or y
    /// runs it, n doesn't, e edits each value in turn and shows both again. Returns false for n; Ctrl-D cancels.
    /// On yes, everything shown since the plan is replaced with one summary line where the terminal allows it.
    @MainActor
    static func review(_ binding: inout Binding, preview: (Binding) async -> [String]) async throws -> Bool {
        let style = Style(for: STDERR_FILENO)
        var shown: [String] = []
        func record(_ line: String) {
            shown.append(line)
        }
        func show(_ binding: Binding) async {
            for line in await planLines(binding, style: style) + preview(binding) + [""] {
                printError(line)
                record(line)
            }
        }
        await show(binding)
        while true {
            let question = "  Run?  ⏎ yes · e edit · n no "
            let key = waitForKey(question, among: ["\n", "y", "n", "e"])
            // The answer as a word, so what was chosen stays on screen.
            let word = switch key {
            case "n": "no"
            case "e": "edit"
            case nil: ""
            default: "yes"
            }
            printError(word)
            record(question + word)
            // Drops the Enter pressed out of habit after y or e, which would otherwise reach the script or keep the
            // first value being edited. n exits, where a stray Enter only gives the shell an empty line.
            if key == "y" || key == "e" {
                pls_discard_enter(300)
            }
            switch key {
            case nil: throw Exit.cancelled
            case "n": return false
            case "e":
                try edit(&binding, record: record)
                await show(binding)
            default:
                replace(shown, with: summaryLine(binding, style: style))
                return true
            }
        }
    }

    /// Shows `question` and waits for one of `keys` (Enter is "\n"), ignoring case and every other key. Keys typed
    /// before the question showed are dropped, so they can't answer it. nil on Ctrl-D or end of input.
    private static func waitForKey(_ question: String, among keys: Set<Character>) -> Character? {
        tcflush(STDIN_FILENO, TCIFLUSH)
        FileHandle.standardError.write(Data(question.utf8))
        while true {
            let byte = pls_read_key()
            guard byte >= 0, byte != 4, let scalar = Unicode.Scalar(UInt32(byte)) else { return nil }
            // Enter is a carriage return where the terminal doesn't turn it into a newline.
            let key = byte == 13 ? "\n" : Character(String(scalar).lowercased())
            if keys.contains(key) {
                return key
            }
        }
    }

    /// Erases `lines`, which end just above the cursor, and prints `summary` in their place. Only on a terminal
    /// whose size is known, when they still fit on screen and `rows(of:columns:)` can count them; otherwise they
    /// stay and nothing is printed.
    private static func replace(_ lines: [String], with summary: String) {
        var size = winsize()
        guard isatty(STDERR_FILENO) != 0, ProcessInfo.processInfo.environment["TERM"] != "dumb",
              ioctl(STDERR_FILENO, TIOCGWINSZ, &size) == 0,
              let rows = rows(of: lines, columns: Int(size.ws_col)), rows < Int(size.ws_row)
        else { return }
        // Up that many rows, back to the line's start, erase to the end of the screen.
        printError("\u{1B}[\(rows)A\r\u{1B}[J" + summary)
    }

    /// How many terminal rows `lines` take at `columns` wide, or nil if that can't be known: a tab, carriage return
    /// or escape code other than color moves the cursor in ways a count can't follow. Color takes no room; emoji
    /// take two columns and every other character one, so other wide characters undercount, which leaves lines
    /// behind instead of erasing more than was shown.
    static func rows(of lines: [String], columns: Int) -> Int? {
        guard columns > 0 else { return nil }
        var total = 0
        for line in lines {
            let plain = line.replacing(/\x1B\[[0-9;]*m/, with: "")
            guard !plain.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
                return nil
            }
            let width = plain.reduce(0) { width, character in
                width + (character.unicodeScalars.first?.properties.isEmojiPresentation == true ? 2 : 1)
            }
            total += max(1, (width + columns - 1) / columns)
        }
        return total
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
    /// `record` gets each line shown, for `review` to replace.
    private static func edit(_ binding: inout Binding, record: (String) -> Void) throws {
        for param in binding.automation.params {
            let current = binding.values[param.name]?.value
            let fitsOnALine = current.map(canPrefill) ?? true
            let prefill = fitsOnALine ? current : nil
            let question = fitsOnALine ? label(param) : label(param, note: "Enter keeps the current value")
            try askUntilValid(question, prefill: prefill, record: record) { (answer: String) throws(BindingError) in
                guard answer != prefill ?? "" else { return }
                try binding.edit(answer.trimmingCharacters(in: .whitespaces), for: param)
            }
        }
    }

    /// Whether `value` can be prefilled for editing: it shows on one line, with no newline, tab or line separator.
    static func canPrefill(_ value: String) -> Bool {
        !Escaping.needsEscaping(value)
    }

    /// Asks `question` until `apply` accepts the answer, showing why it didn't. Ctrl-D cancels. `record` gets each
    /// line shown: the question with its answer, and each reason.
    private static func askUntilValid(
        _ question: String,
        prefill: String? = nil,
        record: (String) -> Void = { _ in },
        apply: (String) throws(BindingError) -> Void
    ) throws {
        while true {
            guard let answer = ask(question, prefill: prefill) else { throw Exit.cancelled }
            record(question + answer)
            do {
                try apply(answer)
                return
            } catch {
                printError("  \(error)")
                record("  \(error)")
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
