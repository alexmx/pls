import Foundation
import Synchronization

/// Everything `pls doctor` reports: loading problems plus checks on the automations that loaded.
public enum Doctor {
    public static func check(_ library: Library) -> [Diagnostic] {
        var found = library.diagnostics
        for automation in library.automations {
            func warn(_ message: String, file: URL = automation.declarationURL) {
                found.append(Diagnostic(.warning, message, file: file, automation: automation.id))
            }
            if automation.description == nil {
                warn("no description, so natural-language requests will never pick it")
            }
            if automation.kind == .shell, Shebang.read(automation.script) == nil {
                warn("has no shebang, so it runs with /bin/zsh", file: automation.script)
            }
            // The model copies example values from descriptions into requests that don't give a value.
            let described = [("description", automation.description)]
                + automation.params.map { ("param \($0.name)'s description", $0.description) }
            for case let (whose, text?) in described {
                if let example = sampleValue(in: text) {
                    warn(
                        "\(whose) gives an example (\"\(example)\"), which the model copies into requests that don't give a value"
                    )
                }
            }
            // The model fills optional choices and numbers even when a request doesn't mention them; a default gives
            // it the value to leave alone.
            for param in automation.params where param.requirement == .optional && param.type.isChoiceOrNumber {
                warn("""
                param \(param.name) is optional with no default, so the model tends to fill one in anyway; give it a \
                default instead (e.g. 0 or a choice meaning "unchanged")
                """)
            }
        }
        return found + syntaxProblems(library.automations)
    }

    /// `syntaxProblem` for each automation, in order. Each check starts a process, so they run side by side: one after
    /// another they took seconds for a 59-automation library.
    static func syntaxProblems(_ automations: [Automation]) -> [Diagnostic] {
        let found = Mutex([Diagnostic?](repeating: nil, count: automations.count))
        DispatchQueue.concurrentPerform(iterations: automations.count) { index in
            let problem = syntaxProblem(automations[index])
            found.withLock { $0[index] = problem }
        }
        return found.withLock { $0.compactMap(\.self) }
    }

    /// "e.g. ~/Pictures/beach.jpg", "like Samantha": an example in a description, with the words after it.
    static func sampleValue(in description: String) -> String? {
        description.firstMatch(of: /(?i)\b(?:e\.g\.|for example|such as|like\b) +\S+(?: \S+)?/).map { String($0.0) }
    }

    /// An error if the script doesn't compile or parse, so it couldn't run: AppleScript through `osacompile`, a zsh,
    /// bash or sh script through its shell's `-n` (zsh without a shebang, as it runs). Other interpreters, and
    /// compiled `.scpt` files, aren't checked.
    static func syntaxProblem(_ automation: Automation) -> Diagnostic? {
        let script = automation.script
        let checker: [String]
        switch automation.kind {
        case .applescript:
            guard script.pathExtension != "scpt" else { return nil }
            checker = ["/usr/bin/osacompile", "-o", "/dev/null"]
        case .shell:
            let interpreter = Shebang.read(script)
            // `#!/usr/bin/env zsh` names the shell after env.
            let program = interpreter.map { $0.first == "/usr/bin/env" ? $0.dropFirst().first : $0.first } ?? "zsh"
            let shell = program.map { URL(filePath: $0).lastPathComponent }
            guard let shell, ["zsh", "bash", "sh"].contains(shell) else { return nil }
            checker = ["/bin/\(shell)", "-n"]
        }
        guard let output = errorOutput(of: checker + [script.path]) else { return nil }
        // "<path>:12: error: Expected … (-2741)" (osacompile), "<path>:4: parse error …" (zsh),
        // "<path>: line 4: syntax error …" (bash, sh): keep the line number and the message.
        let firstLine = output.split(separator: "\n").first.map(String.init) ?? output
        let rest = firstLine.hasPrefix(script.path) ? String(firstLine.dropFirst(script.path.count)) : firstLine
        let parts = rest.wholeMatch(of: /:(?: line )?(\d+): (?:error: )?(.*?)(?: \(-?\d+\))?/)
        let what = automation.kind == .applescript ? "doesn't compile" : "doesn't parse"
        return Diagnostic(
            .error,
            "\(what): \(parts.map { String($0.2) } ?? rest)",
            file: script,
            line: parts.flatMap { Int($0.1) },
            automation: automation.id
        )
    }

    /// What `arguments` writes to stderr when it fails; nil when it succeeds or can't be started.
    private static func errorOutput(of arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Routes each example of `automations` against the whole library and warns about every one the model sends
    /// elsewhere: the examples say what an automation is for, so a miss there means real requests will miss too. Asks
    /// the model once per example, a few seconds each in a big library.
    public static func checkExamples(
        of automations: [Automation], in library: Library, resolver: NLResolver = NLResolver()
    ) async throws(NLResolver.ModelError) -> [Diagnostic] {
        var found: [Diagnostic] = []
        for automation in automations {
            for example in automation.examples {
                let picked = try await resolver.route(example, in: library)
                guard picked?.id != automation.id else { continue }
                found.append(Diagnostic(
                    .warning,
                    "example \"\(example)\" picks \(picked?.id ?? "no automation")",
                    file: automation.declarationURL,
                    automation: automation.id
                ))
            }
        }
        return found
    }
}

private extension ParamType {
    var isChoiceOrNumber: Bool {
        switch self {
        case .enum, .int, .number: true
        case .string, .path, .bool: false
        }
    }
}
