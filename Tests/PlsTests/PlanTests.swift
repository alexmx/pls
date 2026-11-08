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
        # @pls.param folder: path = ~/Desktop -- Where
        # @pls.param quality: int = 80 -- How good
        # @pls.param format: enum(jpg|heic) -- Which format
        # @pls.param note: string? -- Anything
        """
        let metadata = HeaderParser.parse(header, commentPrefix: "#").metadata
        let file = URL(filePath: "/automations/compress.sh")
        return Automation(id: "compress", kind: .shell, source: .file(file), metadata: metadata)
    }()

    private static func binding() throws -> Binding {
        var binding = Binding(defaultsOf: automation, request: "compress my desktop as heic")
        let params = automation.params
        try binding.supply("60", for: params[1], source: .given)
        try binding.supply("heic", for: params[2], source: .request)
        return binding
    }

    @Test func aPlanIsATableWithModelValuesMarked() throws {
        #expect(try planLines(Self.binding(), style: Style(isOn: false)) == [
            "→ Compress images  (compress)",
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
        #expect(lines[3] == "    \u{1B}[2mfolder   ~/Desktop  default\u{1B}[0m")
        #expect(lines[4] == "    quality  60         given")
        #expect(lines[5] == "  \u{1B}[33m● format   heic       from request\u{1B}[0m")
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

    private static let careful = """
    #!/bin/zsh
    # @pls.confirm: true
    # @pls.param quality: int = 80 -- How good
    echo ran
    """

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
