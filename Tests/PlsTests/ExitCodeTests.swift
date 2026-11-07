import Foundation
import Testing

/// The exit codes in SPEC §6, checked by running the built `pls` on a throwaway library with the model off. Exit 1
/// (the model couldn't answer a request) isn't covered: it needs the model to refuse or fail.
@Suite(.timeLimit(.minutes(1)))
struct ExitCodeTests {
    private let home: ThrowawayHome

    init() throws {
        self.home = try ThrowawayHome()
        try home.write("fails.sh", "# @pls.description: Exit with three\nexit 3\n")
        try home.write("killed.sh", "# @pls.description: Kill itself\nkill -TERM $$\n")
        try home.write("no-interpreter.sh", "#!/nonexistent/interpreter\necho hi\n", executable: true)
        try home.write("careful.sh", "# @pls.description: Ask first\n# @pls.confirm: true\necho ran\n")
        try home.write("count.sh", "# @pls.description: Print a number\n# @pls.param n: int\necho $PLS_N\n")
    }

    @Test func aScriptExitsWithItsOwnCode() throws {
        #expect(try pls("run", "fails").status == 3)
    }

    @Test func aScriptEndedBySignalIs128PlusTheSignal() throws {
        #expect(try pls("run", "killed").status == 128 + SIGTERM)
    }

    @Test(arguments: [
        ["run"],
        ["run", "count", "--nope", "1"],
        ["run", "count", "--n", "abc"],
        ["history", "-n", "0"],
        // Asks first, and there's no terminal to ask in.
        ["run", "careful"]
    ])
    func usageErrorsAre64(_ arguments: [String]) throws {
        #expect(try pls(arguments).status == 64)
    }

    /// ArgumentParser's errors read like pls's own: `pls: <message>`, then the usage.
    @Test(arguments: [
        (["run"], "pls: missing expected argument '<id>'\n"),
        (["history", "-n", "0"], "pls: --limit must be at least 1\n"),
        (["run", "--bogus", "x"], "pls: unknown option '--bogus'\n")
    ])
    func argumentErrorsStartWithPls(_ arguments: [String], firstLine: String) throws {
        let result = try pls(arguments)
        #expect(result.stderr.hasPrefix(firstLine))
        #expect(result.stderr.contains("Usage: pls"))
    }

    @Test func anUnknownIDIs65() throws {
        #expect(try pls("run", "nosuch").status == 65)
    }

    @Test func noWordMatchWithoutTheModelIs69() throws {
        #expect(try pls("zzz qqq").status == 69)
    }

    @Test func aScriptThatCantStartIs126() throws {
        #expect(try pls("run", "no-interpreter").status == 126)
    }

    @Test func answeringNoAtTheQuestionIs130() throws {
        #expect(try plsInTerminal(["run", "careful"], answering: "n", after: "Run?") == 130)
    }

    // MARK: Running pls

    private struct Result {
        let status: Int32
        let stderr: String
    }

    /// The `pls` built next to this test bundle.
    private static func binary() -> URL {
        Bundle(for: ThrowawayHome.self).bundleURL.deletingLastPathComponent().appending(path: "pls")
    }

    private func pls(_ arguments: String...) throws -> Result {
        try pls(arguments)
    }

    /// Runs pls with no terminal: stdin is empty, stderr is captured.
    private func pls(_ arguments: [String]) throws -> Result {
        let process = try makeProcess(arguments)
        let stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        try process.run()
        let output = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, stderr: String(decoding: output, as: UTF8.self))
    }

    /// Runs pls in a pseudo-terminal and types `answer` once `prompt` appears; returns the exit status.
    private func plsInTerminal(_ arguments: [String], answering answer: String, after prompt: String) throws -> Int32 {
        var primary: Int32 = 0
        var secondary: Int32 = 0
        try #require(openpty(&primary, &secondary, nil, nil, nil) == 0)
        defer { close(primary) }
        let process = try makeProcess(arguments)
        let terminal = FileHandle(fileDescriptor: secondary, closeOnDealloc: false)
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        try process.run()
        close(secondary)

        try #require(read(primary, until: prompt), "pls never asked \(prompt)")
        _ = (answer + "\n").withCString { write(primary, $0, strlen($0)) }
        // Drain the terminal so pls can't block writing to it.
        while read(primary, until: nil) {}
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Reads the terminal until `text` has appeared (true), or until it closes or stays quiet for 10s (false). With
    /// `text` nil, reads one chunk.
    private func read(_ descriptor: Int32, until text: String?) -> Bool {
        var seen = ""
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            var request = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&request, 1, 10000) > 0 else { return false }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return false }
            guard let text else { return true }
            seen += String(decoding: buffer[..<count], as: UTF8.self)
            if seen.contains(text) {
                return true
            }
        }
    }

    private func makeProcess(_ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = Self.binary()
        process.arguments = arguments
        process.currentDirectoryURL = home.url
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PLS_") }
        environment["PLS_HOME"] = home.url.path
        environment["PLS_MODEL"] = "off"
        process.environment = environment
        return process
    }
}

/// A pls home in the temp directory, removed when the value is released.
private final class ThrowawayHome {
    let url = FileManager.default.temporaryDirectory.appending(path: "pls-exit-tests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: "automations"), withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ name: String, _ content: String, executable: Bool = false) throws {
        let file = url.appending(path: "automations/\(name)")
        try content.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
    }
}
