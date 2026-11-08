import Foundation
@testable import pls
import PlsCore
import Testing

/// The plan shown before a run and by --dry-run: a table of values, with the model's marked to check.
@Suite(.timeLimit(.minutes(1)))
struct PlanTests {
    private static let automation = {
        let header = """
        # @pls.name: Compress images
        # @pls.description: Make images smaller
        # @pls.param folder: path = ~/Desktop -- Where
        # @pls.param quality: int = 80 -- How good
        # @pls.param format: enum(jpg|heic) -- Which format
        # @pls.param note: string? -- Anything
        """
        let metadata = HeaderParser.parse(header, commentPrefix: "#").metadata
        let file = URL(filePath: "/automations/compress.sh")
        return Automation(id: "compress", kind: .shell, source: .file(file), metadata: metadata)
    }()

    /// Asks before running; for the tests that run the built pls.
    private static let careful = """
    #!/bin/zsh
    # @pls.confirm: true
    # @pls.param quality: int = 80 -- How good
    echo ran
    """

    private static func binding() throws -> Binding {
        var binding = Binding(defaultsOf: automation, request: "compress my desktop as heic")
        try binding.supply("60", for: param("quality"), source: .given)
        try binding.supply("heic", for: param("format"), source: .request)
        return binding
    }

    private static func param(_ name: String) throws -> Param {
        try #require(automation.params.first { $0.name == name })
    }

    @Test func aPlanIsATableWithModelValuesMarked() throws {
        #expect(try planLines(Self.binding(), style: Style(isOn: false)) == [
            "→ Compress images  (compress)",
            "  Make images smaller",
            "",
            "    PARAM    VALUE      FROM",
            "    folder   ~/Desktop  default",
            "    quality  60         given",
            "  ● format   heic       from request",
            "    note     (empty)"
        ])
    }

    @Test func colorDimsDefaultsAndHighlightsModelValues() throws {
        let lines = try planLines(Self.binding(), style: Style(isOn: true))
        #expect(lines[0] == "→ \u{1B}[1mCompress images\u{1B}[0m  \u{1B}[2m(compress)\u{1B}[0m")
        #expect(lines[1] == "  \u{1B}[2mMake images smaller\u{1B}[0m")
        #expect(lines[4] == "    \u{1B}[2mfolder   ~/Desktop  default\u{1B}[0m")
        #expect(lines[5] == "    quality  60         given")
        #expect(lines[6] == "  \u{1B}[33m● format   heic       from request\u{1B}[0m")
    }

    @Test func anAutomationWithoutParamsShowsOnlyItsName() {
        let file = URL(filePath: "/automations/lock.sh")
        let automation = Automation(id: "lock", kind: .shell, source: .file(file), metadata: Metadata())
        #expect(planLines(Binding(defaultsOf: automation), style: Style(isOn: false)) == ["→ Lock  (lock)"])
    }

    @Test func aPipedDryRunIsPlainText() async throws {
        let pls = try BuiltPls()
        try pls.write("careful.sh", Self.careful, executable: true)
        let result = try await pls.run("run", "careful", "--dry-run")
        #expect(result.stdout
            .hasPrefix("→ Careful  (careful)\n\n    PARAM    VALUE  FROM\n    quality  80     default\n"))
    }

    @Test func theQuestionInATerminalIsStyled() async throws {
        let pls = try BuiltPls()
        try pls.write("careful.sh", Self.careful, executable: true)
        let result = try await pls.runInTerminal(["run", "careful"], typing: "n\n", after: "Run?")
        #expect(result.output.contains("    \u{1B}[2mquality  80     default\u{1B}[0m"))
        #expect(result.output.contains("Run?  ⏎ yes · e edit · n no"))
    }

    @Test func aSummaryIsOneLineOfTheValues() throws {
        #expect(try summaryLine(Self.binding(), style: Style(isOn: false))
            == "→ Compress images  folder=~/Desktop  quality=60  format=heic")
    }

    @Test func yesReplacesThePlanWithTheSummary() async throws {
        let pls = try BuiltPls()
        try pls.write("careful.sh", Self.careful, executable: true)
        let result = try await pls.runInTerminal(["run", "careful"], typing: "y", after: "Run?")
        // Title, blank, header, a row, blank and the question.
        #expect(result.output.contains("\u{1B}[6A\r\u{1B}[J→ \u{1B}[1mCareful\u{1B}[0m  quality=80\r\nran"))
    }

    @Test func theSummaryAlsoReplacesWhatEditingShowed() async throws {
        let pls = try BuiltPls()
        try pls.write("careful.sh", Self.careful, executable: true)
        // e with the Enter pressed out of habit, which mustn't keep the value being edited; Ctrl-U clears it.
        let result = try await pls.runInTerminal(
            ["run", "careful"],
            answering: [
                (after: "Run?", typing: "e\n"),
                (after: "quality", typing: "\u{15}70\n"),
                (after: "Run?", typing: "y")
            ]
        )
        // The plan twice, with the edit question between.
        #expect(result.output.contains("\u{1B}[13A\r\u{1B}[J→ \u{1B}[1mCareful\u{1B}[0m  quality=70"))
    }

    @Test func noLeavesThePlan() async throws {
        let pls = try BuiltPls()
        try pls.write("careful.sh", Self.careful, executable: true)
        let result = try await pls.runInTerminal(["run", "careful"], typing: "n", after: "Run?")
        #expect(!result.output.contains("\u{1B}[J"))
    }

    @Test func otherKeysAreIgnoredAndCaseIsNot() async throws {
        let pls = try BuiltPls()
        try pls.write("careful.sh", Self.careful, executable: true)
        let result = try await pls.runInTerminal(["run", "careful"], typing: "xN", after: "Run?")
        #expect(result.status == 0)
        #expect(result.output.contains("Run?  ⏎ yes · e edit · n no no"))
    }

    @Test func theEnterAfterYDoesntReachTheScript() async throws {
        let pls = try BuiltPls()
        try pls.write("reads.sh", """
        #!/bin/zsh
        # @pls.confirm: true
        echo 'name?'
        read -r name
        echo "got:[$name]"
        """, executable: true)
        let result = try await pls.runInTerminal(
            ["run", "reads"], answering: [(after: "Run?", typing: "y\n"), (after: "name?", typing: "alex\n")]
        )
        #expect(result.output.contains("got:[alex]"))
    }

    @Test(arguments: [
        (["", "abc"], 10, 2),
        (["0123456789"], 10, 1),
        (["0123456789a"], 10, 2),
        (["\u{1B}[2m0123456789\u{1B}[0m"], 10, 1),
        (["🙂🙂🙂🙂🙂"], 10, 1),
        (["🙂🙂🙂🙂🙂🙂"], 10, 2)
    ])
    func rowsCountWrappedLines(lines: [String], columns: Int, rows: Int) {
        #expect(Prompt.rows(of: lines, columns: columns) == rows)
    }

    @Test(arguments: [(["a\tb"], 80), (["\u{1B}[2Aup"], 80), (["a\rb"], 80), (["abc"], 0)])
    func rowsAreUnknownForCursorMovesOrNoWidth(lines: [String], columns: Int) {
        #expect(Prompt.rows(of: lines, columns: columns) == nil)
    }

    @Test func colorIsOnOnlyForATerminalWithoutNoColor() throws {
        var (primary, secondary): (Int32, Int32) = (0, 0)
        try #require(openpty(&primary, &secondary, nil, nil, nil) == 0)
        defer {
            close(primary)
            close(secondary)
        }
        #expect(Style(for: secondary, environment: [:]).isOn)
        #expect(Style(for: secondary, environment: ["NO_COLOR": ""]).isOn)
        #expect(!Style(for: secondary, environment: ["NO_COLOR": "1"]).isOn)
        let pipe = Pipe()
        #expect(!Style(for: pipe.fileHandleForWriting.fileDescriptor, environment: [:]).isOn)
    }
}
