import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct RunTests {
    // MARK: invocation

    private func binding(_ home: TempHome, _ id: String, arguments: [String] = []) throws -> Binding {
        let library = Library.load(home: home.url)
        let automation = try #require(library.automation(id: id), "\(library.diagnostics)")
        return try ParamBinder.bind(automation, arguments: arguments)
    }

    private func invocation(_ home: TempHome, _ id: String, arguments: [String] = []) throws -> Invocation {
        try Invocation(binding(home, id, arguments: arguments), homeDirectory: "/Users/me")
    }

    @Test func executableScriptRunsDirectly() throws {
        let home = try TempHome()
        let script = try home.write("a.sh", "#!/bin/zsh\n# @pls.param x: string\n", executable: true)
        let run = try invocation(home, "a", arguments: ["hi"])
        #expect(run.executable == script)
        #expect(run.arguments == ["hi"])
    }

    /// The kernel can't exec a file without a shebang (ENOEXEC); shells fall back to sh, pls to zsh.
    @Test func executableScriptWithoutShebangUsesZsh() throws {
        let home = try TempHome()
        let script = try home.write("a.sh", "echo hi\n", executable: true)
        let run = try invocation(home, "a")
        #expect(run.executable.path == "/bin/zsh")
        #expect(run.arguments == [script.path])
    }

    @Test func nonExecutableScriptUsesItsShebang() throws {
        let home = try TempHome()
        let script = try home.write("a.py", "#!/usr/bin/env python3 -u\nprint(1)\n")
        let run = try invocation(home, "a")
        #expect(run.executable.path == "/usr/bin/env")
        #expect(run.arguments == ["python3", "-u", script.path])
    }

    @Test func nonExecutableScriptWithoutShebangUsesZsh() throws {
        let home = try TempHome()
        let script = try home.write("a.sh", "echo hi\n")
        let run = try invocation(home, "a")
        #expect(run.executable.path == "/bin/zsh")
        #expect(run.arguments == [script.path])
    }

    @Test func appleScriptUsesOsascript() throws {
        let home = try TempHome()
        let script = try home.write("a.applescript", "-- @pls.param mode: enum(dark|light)\n")
        let run = try invocation(home, "a", arguments: ["dark"])
        #expect(run.executable.path == "/usr/bin/osascript")
        #expect(run.arguments == [script.path, "dark"])
    }

    @Test func valuesAndVariables() throws {
        let home = try TempHome()
        try home.write("a.sh", """
        #!/bin/zsh
        # @pls.param folder: path = ~/Desktop
        # @pls.param name: string?
        # @pls.param older_than_days: int = 30
        """, executable: true)

        let run = try invocation(home, "a")

        #expect(run.arguments == ["/Users/me/Desktop", "", "30"])
        #expect(run.variables == ["PLS_ID": "a", "PLS_FOLDER": "/Users/me/Desktop", "PLS_OLDER_THAN_DAYS": "30"])
    }

    @Test func folderAutomationGetsItsDirectory() throws {
        let home = try TempHome()
        try home.write("tool/manifest.yaml", "entry: run.sh\n")
        try home.write("tool/run.sh", "", executable: true)
        let run = try invocation(home, "tool")
        #expect(run.variables["PLS_AUTOMATION_DIR"] == home.url.appending(path: "automations/tool").path)
    }

    @Test func environmentDropsStaleVariables() throws {
        let home = try TempHome()
        try home.write("a.sh", "# @pls.param name: string?\n", executable: true)
        let run = try invocation(home, "a")
        let inherited = [
            "PATH": "/bin", "PLS_NAME": "stale", "PLS_ID": "old", "PLS_PORT": "from a calling automation",
            "PLS_AUTOMATION_DIR": "/elsewhere", "PLS_HOME": "/my/library", "PLS_MODEL": "off"
        ]
        // Only pls's settings survive, so `pls run` inside a script works the same way and nothing else leaks in.
        #expect(run.environment(inheriting: inherited) == [
            "PATH": "/bin", "PLS_ID": "a", "PLS_HOME": "/my/library", "PLS_MODEL": "off"
        ])
    }

    @Test(arguments: [
        ("~", "/Users/me"),
        ("~/x y", "/Users/me/x y"),
        ("/abs", "/abs"),
        ("rel/~", "rel/~")
    ])
    func tildeExpansion(path: String, expected: String) {
        #expect(Invocation.expandTilde(path, homeDirectory: "/Users/me") == expected)
    }

    @Test func commandLineQuotesWhatNeedsIt() throws {
        let home = try TempHome()
        let script = try home.write(
            "a.sh", "#!/bin/zsh\n# @pls.param a: string\n# @pls.param b: string?\n", executable: true
        )
        let run = try invocation(home, "a", arguments: ["it's here"])
        #expect(run.commandLine == "\(script.path) 'it'\\''s here' ''")
    }

    @Test func aPreviewInvocationSetsPlsPreview() throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\n")
        let binding = try binding(home, "a")
        #expect(Invocation(binding, preview: true).variables["PLS_PREVIEW"] == "1")
        #expect(Invocation(binding).variables["PLS_PREVIEW"] == nil)
    }

    // MARK: runner

    /// Runs the automation with `OUT` pointing at a file the script writes to; returns (status, file contents).
    private func run(
        _ home: TempHome, _ id: String, arguments: [String] = [], environment: [String: String] = [:]
    ) async throws -> (Int32, String) {
        let out = home.url.appending(path: "out.txt")
        let status = try await Runner.run(
            invocation(home, id, arguments: arguments),
            environment: environment.merging(["OUT": out.path, "PATH": "/usr/bin:/bin"]) { $1 }
        )
        return (status, (try? String(contentsOf: out, encoding: .utf8)) ?? "")
    }

    @Test func scriptGetsArgumentsAndVariables() async throws {
        let home = try TempHome()
        try home.write("a.sh", """
        #!/bin/zsh
        # @pls.param word: string
        # @pls.param name: string?
        printf '%s|' "$@" > "$OUT"
        echo "$PLS_WORD ${PLS_NAME-unset} $PLS_ID" >> "$OUT"
        """, executable: true)

        let (status, output) = try await run(home, "a", arguments: ["two words"], environment: ["PLS_NAME": "stale"])

        #expect(status == 0)
        #expect(output == "two words||two words unset a\n")
    }

    @Test func exitStatusPassesThrough() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\nexit 3\n", executable: true)
        #expect(try await run(home, "a").0 == 3)
    }

    @Test func signalBecomes128PlusTheSignal() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\nkill -TERM $$\n", executable: true)
        #expect(try await run(home, "a").0 == 128 + SIGTERM)
    }

    @Test func appleScriptGetsItsParamsInOrder() async throws {
        let home = try TempHome()
        try home.write("a.applescript", """
        -- @pls.param first: string
        -- @pls.param second: string
        on run argv
            do shell script "printf '%s|%s' " & quoted form of item 1 of argv & " " & ¬
                quoted form of item 2 of argv & " > " & quoted form of (system attribute "OUT")
        end run
        """)

        let (status, output) = try await run(home, "a", arguments: ["one", "two words"])

        #expect(status == 0)
        #expect(output == "one|two words")
    }

    /// A script must stay in pls's process group: that's the terminal's foreground group, so Ctrl-C reaches the
    /// script and it can read from the terminal (a background group gets stopped by SIGTTIN).
    @Test func scriptStaysInTheCallersProcessGroup() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\nps -o pgid= -p $$ | tr -d ' ' > \"$OUT\"\n", executable: true)
        let (status, output) = try await run(home, "a")
        #expect(status == 0)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == String(getpgrp()))
    }

    /// pls ignores Ctrl-C while a script runs; the script must still get the default behavior and stop.
    @Test func scriptGetsDefaultInterruptHandlingWhilePlsIgnoresIt() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\nkill -INT $$\nsleep 1\nexit 0\n", executable: true)
        let previous = signal(SIGINT, SIG_IGN)
        defer { signal(SIGINT, previous) }
        #expect(try await run(home, "a").0 == 128 + SIGINT)
    }

    @Test func missingProgramIsALaunchError() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/nonexistent/interpreter\n")
        await #expect(throws: Runner.LaunchError.self) { try await run(home, "a") }
    }

    // MARK: recorded runs

    @Test func recordedRunIsWrittenToHistory() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\n# @pls.param port: int\nexit 3\n", executable: true)
        let history = HistoryStore(file: home.url.appending(path: "history.jsonl"))

        let outcome = try await Runner.run(binding(home, "a", arguments: ["80"]), via: .again, history: history)

        #expect(outcome.status == 3)
        #expect(outcome.historyError == nil)
        let entry = try #require(history.recent(1).first)
        #expect((entry.id, entry.params, entry.chosen, entry.via, entry.exit) == (
            "a",
            ["port": "80"],
            ["port"],
            .again,
            3
        ))
        #expect(entry.seconds >= 0)
    }

    @Test func unwritableHistoryKeepsTheStatusAndReportsTheError() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\nexit 4\n", executable: true)
        let file = home.url.appending(path: "history.jsonl")
        try Data().write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)

        let outcome = try await Runner.run(binding(home, "a"), via: .run, history: HistoryStore(file: file))

        #expect(outcome.status == 4)
        #expect(outcome.historyError != nil)
    }

    @Test func scriptThatCantStartIsNotRecorded() async throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/nonexistent/interpreter\n")
        let history = HistoryStore(file: home.url.appending(path: "history.jsonl"))
        await #expect(throws: Runner.LaunchError.self) { try await Runner.run(
            binding(home, "a"),
            via: .run,
            history: history
        ) }
        #expect(history.recent(1).isEmpty)
    }
}
