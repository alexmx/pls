import Foundation
import Testing

/// pls's exit codes (`Exit`, plus the script's own), checked by running the built `pls` on a throwaway library with
/// the model off. Exit 1 (the model couldn't answer a request) isn't covered: it needs the model to refuse or fail.
@Suite(.timeLimit(.minutes(1)))
struct ExitCodeTests {
    private let pls: BuiltPls

    init() throws {
        self.pls = try BuiltPls()
        try pls.write("fails.sh", "# @pls.description: Exit with three\nexit 3\n")
        try pls.write("killed.sh", "# @pls.description: Kill itself\nkill -TERM $$\n")
        try pls.write("no-interpreter.sh", "#!/nonexistent/interpreter\necho hi\n", executable: true)
        try pls.write("careful.sh", "# @pls.description: Ask first\n# @pls.confirm: true\necho ran\n")
        try pls.write("power.sh", """
        # @pls.description: Shut down or cancel
        # @pls.param action: enum(shutdown|cancel)
        # @pls.confirm: action=shutdown
        echo $PLS_ACTION
        """)
        try pls.write("count.sh", "# @pls.description: Print a number\n# @pls.param n: int\necho $PLS_N\n")
        try pls.write(
            "applescript-fails.applescript",
            "-- @pls.description: Fail\non run argv\n\terror \"No image at /x.jpg\" number 3\nend run\n"
        )
    }

    /// `confirm: action=shutdown` asks only for shutdown, so cancel runs without a terminal to ask in.
    @Test func aChoiceThatDoesntAskRunsWithoutATerminal() async throws {
        let result = try await pls.run("run", "power", "cancel")
        #expect(result.status == 0)
        #expect(result.stdout == "cancel\n")
    }

    @Test func aScriptExitsWithItsOwnCode() async throws {
        #expect(try await pls.run("run", "fails").status == 3)
    }

    /// osascript's location and error number around the message are left out; it exits 1 whatever the number.
    @Test func aFailingAppleScriptShowsJustItsMessage() async throws {
        let result = try await pls.run("run", "applescript-fails")
        #expect(result.status == 1)
        #expect(result.stderr == "No image at /x.jpg\n")
    }

    @Test func aScriptEndedBySignalIs128PlusTheSignal() async throws {
        #expect(try await pls.run("run", "killed").status == 128 + SIGTERM)
    }

    @Test(arguments: [
        ["run"],
        ["run", "count", "--nope", "1"],
        ["run", "count", "--n", "abc"],
        ["history", "-n", "0"],
        // Asks first, and there's no terminal to ask in.
        ["run", "careful"],
        ["run", "power", "shutdown"]
    ])
    func usageErrorsAre64(_ arguments: [String]) async throws {
        #expect(try await pls.run(arguments).status == 64)
    }

    /// ArgumentParser's errors read like pls's own: `pls: <message>`, then the usage.
    @Test(arguments: [
        (["run"], "pls: missing expected argument '<id>'\n"),
        (["history", "-n", "0"], "pls: --limit must be at least 1\n"),
        (["run", "--bogus", "x"], "pls: unknown option '--bogus'\n"),
        // A request, parsed by its own command.
        (["foo", "--dry-run=x"], "pls: the option '--dry-run' does not take any value")
    ])
    func argumentErrorsStartWithPls(_ arguments: [String], firstLine: String) async throws {
        let result = try await pls.run(arguments)
        #expect(result.stderr.hasPrefix(firstLine))
        #expect(result.stderr.contains("Usage: pls"))
    }

    @Test func anUnknownIDIs65() async throws {
        #expect(try await pls.run("run", "nosuch").status == 65)
        #expect(try await pls.run("doctor", "--examples", "nosuch").status == 65)
    }

    @Test func noWordMatchWithoutTheModelIs69() async throws {
        #expect(try await pls.run("zzz qqq").status == 69)
    }

    @Test func aScriptThatCantStartIs126() async throws {
        #expect(try await pls.run("run", "no-interpreter").status == 126)
    }

    @Test func answeringNoAtTheQuestionIs130() async throws {
        #expect(try await pls.runInTerminal(["run", "careful"], typing: "n\n", after: "Run?").status == 130)
    }
}
