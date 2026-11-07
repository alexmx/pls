import Foundation
import Subprocess
import Testing

/// What only a real terminal shows: the built pls runs under `script`, which makes a pseudo-terminal its controlling
/// terminal, as a shell's is. A script must stay in the terminal's foreground process group: there Ctrl-C reaches it,
/// and it can read what's typed instead of being stopped for reading from the background.
@Suite(.timeLimit(.minutes(1)))
struct TerminalTests {
    private let home = FileManager.default.temporaryDirectory.appending(path: "pls-terminal-tests-\(UUID().uuidString)")

    init() throws {
        let automations = home.appending(path: "automations")
        try FileManager.default.createDirectory(at: automations, withIntermediateDirectories: true)
        try "#!/bin/zsh\n# @pls.description: Wait\necho ready\nsleep 30\necho finished\n"
            .write(to: automations.appending(path: "waits.sh"), atomically: true, encoding: .utf8)
        try "#!/bin/zsh\n# @pls.description: Ask\necho 'name?'\nread -r name\necho \"got:$name\"\n"
            .write(to: automations.appending(path: "asks.sh"), atomically: true, encoding: .utf8)
    }

    @Test func ctrlCEndsTheScriptWith130() async throws {
        let result = try await plsInTerminal(["run", "waits"], typing: "\u{03}", after: "ready")
        #expect(result.status == 130)
        #expect(!result.output.contains("finished"))
    }

    @Test func aScriptReadsWhatIsTypedInTheTerminal() async throws {
        let result = try await plsInTerminal(["run", "asks"], typing: "alex\n", after: "name?")
        #expect(result.status == 0)
        #expect(result.output.contains("got:alex"))
    }

    /// Runs pls in a terminal and types `keys` once `prompt` appears; returns the exit status and everything shown.
    private func plsInTerminal(
        _ arguments: [String], typing keys: String, after prompt: String
    ) async throws -> (status: Int32, output: String) {
        var variables = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PLS_") }
        variables["PLS_HOME"] = home.path
        variables["PLS_MODEL"] = "off"
        let environment = Environment.custom(Dictionary(uniqueKeysWithValues: variables.compactMap { key, value in
            Environment.Key(rawValue: key).map { ($0, value) }
        }))
        let result = try await Subprocess.run(
            .path("/usr/bin/script"),
            arguments: Arguments(["-q", "/dev/null", ExitCodeTests.binary().path] + arguments),
            environment: environment,
            input: .inputWriter,
            output: .sequence,
            error: .discarded
        ) { execution in
            // Input stays open until pls ends: closing it would type Ctrl-D into the terminal.
            var shown = ""
            var typed = false
            for try await chunk in execution.standardOutput {
                shown += chunk.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
                if !typed, shown.contains(prompt) {
                    _ = try await execution.standardInputWriter.write(Array(keys.utf8))
                    typed = true
                }
            }
            return shown
        }
        let status: Int32 = switch result.terminationStatus {
        case let .exited(code): code
        case let .signaled(signal): 128 + signal
        }
        return (status, result.closureResult)
    }
}
