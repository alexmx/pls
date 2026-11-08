import Foundation
@testable import PlsCore
import Subprocess
import System

/// The `pls` built next to this test bundle, run on a throwaway library of its own with the model off. The library is
/// removed when the value is released.
final class BuiltPls {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static let binary = Bundle(for: BuiltPls.self).bundleURL.deletingLastPathComponent().appending(path: "pls")

    let home = FileManager.default.temporaryDirectory.appending(path: "pls-tests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(
            at: home.appending(path: "automations"),
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    /// Writes `automations/<name>`.
    func write(_ name: String, _ content: String, executable: Bool = false) throws {
        let file = home.appending(path: "automations/\(name)")
        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
    }

    /// Runs pls with no terminal: stdin is empty, stdout and stderr are captured.
    func run(_ arguments: String...) async throws -> Result {
        try await run(arguments)
    }

    func run(_ arguments: [String]) async throws -> Result {
        let result = try await Subprocess.run(
            .path(FilePath(Self.binary.path)),
            arguments: Arguments(arguments),
            environment: environment,
            workingDirectory: FilePath(home.path),
            input: .none,
            output: .string(limit: 1 << 20),
            error: .string(limit: 1 << 20)
        )
        return Result(
            status: result.terminationStatus.shellCode,
            stdout: result.standardOutput,
            stderr: result.standardError
        )
    }

    /// Runs pls in a real terminal and types `keys` once `prompt` appears; returns the exit status and everything
    /// shown.
    /// It runs under `script`, which makes a pseudo-terminal pls's controlling terminal, as a shell's is: only then do
    /// Ctrl-C and reading from the terminal behave as for a user. The terminal is 80×24, as `script` would otherwise
    /// leave its size unknown.
    func runInTerminal(
        _ arguments: [String], typing keys: String, after prompt: String
    ) async throws -> (status: Int32, output: String) {
        try await runInTerminal(arguments, answering: [(after: prompt, typing: keys)])
    }

    /// Like `runInTerminal(_:typing:after:)` for several questions in turn: each answer is typed once its prompt
    /// appears after the previous answer's.
    func runInTerminal(
        _ arguments: [String], answering answers: [(after: String, typing: String)]
    ) async throws -> (status: Int32, output: String) {
        let result = try await Subprocess.run(
            .path("/usr/bin/script"),
            arguments: Arguments(
                ["-q", "/dev/null", "/bin/sh", "-c", #"stty cols 80 rows 24 && exec "$0" "$@""#, Self.binary.path]
                    + arguments
            ),
            environment: environment,
            workingDirectory: FilePath(home.path),
            input: .inputWriter,
            output: .sequence,
            error: .discarded
        ) { execution in
            // Input stays open until pls ends: closing it would type Ctrl-D into the terminal.
            var shown = ""
            var answered = 0
            var searchedTo = 0 // in UTF-8 bytes: indices don't survive appending
            for try await chunk in execution.standardOutput {
                shown += chunk.withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
                while answered < answers.count,
                      let found = shown[shown.utf8.index(shown.startIndex, offsetBy: searchedTo)...]
                          .range(of: answers[answered].after) {
                    _ = try await execution.standardInputWriter.write(Array(answers[answered].typing.utf8))
                    searchedTo = shown.utf8.distance(from: shown.startIndex, to: found.upperBound)
                    answered += 1
                }
            }
            return shown
        }
        return (result.terminationStatus.shellCode, result.closureResult)
    }

    /// The test process's environment without any PLS_ settings or NO_COLOR, plus this library and the model turned
    /// off.
    private var environment: Environment {
        var variables = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PLS_") && $0.key != "NO_COLOR" }
        variables["PLS_HOME"] = home.path
        variables["PLS_MODEL"] = "off"
        return .exactly(variables)
    }
}
