import Foundation
import Testing

/// `@pls.preview`: pls runs the script with PLS_PREVIEW=1 for --dry-run and before asking, and shows what it prints.
@Suite(.timeLimit(.minutes(1)))
struct PreviewTests {
    private let pls: BuiltPls

    init() throws {
        self.pls = try BuiltPls()
        // Leaves a file when it really runs, so a preview that changed anything would show.
        try pls.write("marker.sh", """
        #!/bin/zsh
        # @pls.description: Leave a marker
        # @pls.preview: true
        # @pls.confirm: true
        if [[ -n $PLS_PREVIEW ]]; then
          echo "Would leave a marker"
          exit 0
        fi
        touch ran
        """)
        try pls.write("plain.sh", "#!/bin/zsh\n# @pls.description: No preview\ntouch ran\n")
        try pls.write(
            "broken.sh",
            "#!/bin/zsh\n# @pls.description: Preview fails\n# @pls.preview: true\necho nope\nexit 3\n"
        )
    }

    private var ran: Bool {
        FileManager.default.fileExists(atPath: pls.home.appending(path: "ran").path)
    }

    @Test func aDryRunShowsThePreviewAndChangesNothing() async throws {
        let result = try await pls.run("run", "marker", "--dry-run")
        #expect(result.stdout.hasSuffix("\n  preview\n    Would leave a marker\n"))
        #expect(!ran)
    }

    @Test func aScriptWithoutPreviewIsntRunForADryRun() async throws {
        #expect(try await !pls.run("run", "plain", "--dry-run").stdout.contains("\n  preview\n"))
        #expect(!ran)
    }

    @Test func thePreviewComesBeforeTheQuestion() async throws {
        let result = try await pls.runInTerminal(["run", "marker"], typing: "n", after: "Run?")
        #expect(result.status == 0)
        // The line editor adds terminal control codes around the question, so check the order, not the exact text.
        let preview = try #require(result.output.range(of: "Would leave a marker"))
        let question = try #require(result.output.range(of: "Run?  ⏎ yes · e edit · n no"))
        #expect(preview.upperBound < question.lowerBound)
        #expect(!ran)
    }

    @Test func aFailingPreviewSaysSo() async throws {
        let result = try await pls.run("run", "broken", "--dry-run")
        #expect(result.stdout.hasSuffix("  preview\n    nope\n    (the preview failed with exit 3)\n"))
    }
}
