import Testing

/// What only a real terminal shows (see `BuiltPls.runInTerminal`): a script must stay in the terminal's foreground
/// process group, where Ctrl-C reaches it and it can read what's typed instead of being stopped for reading from the
/// background.
@Suite(.timeLimit(.minutes(1)))
struct TerminalTests {
    private let pls: BuiltPls

    init() throws {
        self.pls = try BuiltPls()
        try pls.write("waits.sh", "#!/bin/zsh\n# @pls.description: Wait\necho ready\nsleep 30\necho finished\n")
        try pls.write(
            "asks.sh",
            "#!/bin/zsh\n# @pls.description: Ask\necho 'name?'\nread -r name\necho \"got:$name\"\n"
        )
    }

    @Test func ctrlCEndsTheScriptWith130() async throws {
        let result = try await pls.runInTerminal(["run", "waits"], typing: "\u{03}", after: "ready")
        #expect(result.status == 130)
        #expect(!result.output.contains("finished"))
    }

    @Test func aScriptReadsWhatIsTypedInTheTerminal() async throws {
        let result = try await pls.runInTerminal(["run", "asks"], typing: "alex\n", after: "name?")
        #expect(result.status == 0)
        #expect(result.output.contains("got:alex"))
    }
}
