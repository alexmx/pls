import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DoctorTests {
    @Test func healthyLibraryHasNoProblems() throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\n# @pls.description: A\n")
        try home.write("b.sh", "#!/bin/bash\n# @pls.description: B\n", executable: true)
        try home.write("c.applescript", "-- @pls.description: C\n")
        try home.write("d/manifest.yaml", "description: D\nentry: run.sh\n")
        try home.write("d/run.sh", "#!/bin/zsh\n")

        #expect(Doctor.check(Library.load(home: home.url)).isEmpty)
    }

    /// A script that couldn't run is an error at the line its compiler or shell names.
    @Test(arguments: [
        (
            "a.applescript",
            "-- @pls.description: A\non run\n\tset x to\nend run\n",
            3,
            "doesn't compile: Expected expression but found end of line."
        ),
        (
            "b.sh",
            "#!/bin/zsh\n# @pls.description: B\nif true; then\n  echo hi\n",
            5,
            "doesn't parse: parse error near `\\n'"
        ),
        (
            "c.sh",
            "#!/usr/bin/env bash\n# @pls.description: C\necho hi )\n",
            3,
            "doesn't parse: syntax error near unexpected token `)'"
        ),
        ("d.sh", "# @pls.description: D\nfor x in; do\n", 3, "doesn't parse: parse error near `\\n'")
    ])
    func aScriptThatDoesntParseIsAnError(file name: String, content: String, line: Int, message: String) throws {
        let home = try TempHome()
        let file = try home.write(name, content)
        let id = (name as NSString).deletingPathExtension
        let problems = Doctor.check(Library.load(home: home.url)).filter { $0.severity == .error }
        #expect(problems == [Diagnostic(.error, message, file: file, line: line, automation: id)])
    }

    /// The model fills an optional choice or number even when the request doesn't say; text and paths are fine.
    @Test func anOptionalChoiceOrNumberWithoutDefaultIsAWarning() throws {
        let home = try TempHome()
        let file = try home.write("a.sh", """
        #!/bin/zsh
        # @pls.description: A
        # @pls.param port: int(1...65535)?
        # @pls.param format: enum(png|jpg)?
        # @pls.param size: int = 0
        # @pls.param label: string?
        # @pls.param folder: path?
        """)
        let messages = Doctor.check(Library.load(home: home.url)).map(\.message)
        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.contains("optional with no default") })
        #expect(messages.first?.hasPrefix("param port ") == true)
        #expect(Doctor.check(Library.load(home: home.url)).allSatisfy { $0.file == file && $0.severity == .warning })
    }

    /// "like Samantha" became the voice for requests that named none; examples in descriptions leak into fills.
    @Test func anExampleInADescriptionIsAWarning() throws {
        let home = try TempHome()
        try home.write("a.sh", """
        #!/bin/zsh
        # @pls.description: Resize images, e.g. to 1200 pixels
        # @pls.param voice: string? -- A system voice, like Samantha
        # @pls.param text: string -- The words to speak
        """)
        #expect(Doctor.check(Library.load(home: home.url)).map(\.message) == [
            "description gives an example (\"e.g. to 1200\"), which the model copies into requests that don't give a value",
            "param voice's description gives an example (\"like Samantha\"), which the model copies into requests that don't give a value"
        ])
    }

    @Test(arguments: [
        "Kill whatever process is listening on a TCP port",
        "Clean likely junk",
        "Unlike Finder, keep originals"
    ])
    func aDescriptionWithoutAnExampleIsFine(_ description: String) {
        #expect(Doctor.sampleValue(in: description) == nil)
    }

    /// Only shells are checked: pls can't tell what's valid for any other interpreter.
    @Test func otherInterpretersArentChecked() throws {
        let home = try TempHome()
        try home.write("a.py", "#!/usr/bin/env python3\n# @pls.description: A\nthis is not ( python\n")
        #expect(Doctor.check(Library.load(home: home.url)).isEmpty)
    }

    @Test func includesLoadingProblems() throws {
        let home = try TempHome()
        try home.write("bad.sh", "# @pls.param x: nope\n")
        let library = Library.load(home: home.url)
        #expect(Doctor.check(library) == library.diagnostics)
        #expect(!library.diagnostics.isEmpty)
    }

    @Test func missingDescription() throws {
        let home = try TempHome()
        let file = try home.write("x.sh", "#!/bin/zsh\n")
        #expect(Doctor.check(Library.load(home: home.url)) == [
            Diagnostic(
                .warning, "no description, so natural-language requests will never pick it", file: file, automation: "x"
            )
        ])
    }

    @Test func folderProblemsPointAtTheManifest() throws {
        let home = try TempHome()
        let manifest = try home.write("x/manifest.yaml", "entry: run.sh\nicon: fire\n")
        try home.write("x/run.sh", "#!/bin/zsh\n")
        let files = Doctor.check(Library.load(home: home.url)).map(\.file)
        #expect(files == [manifest, manifest])
    }

    /// A bare `#!` names no interpreter, so the script runs with zsh; doctor must say so, like for no shebang.
    @Test func bareShebangCountsAsNone() throws {
        let home = try TempHome()
        try home.write("x/manifest.yaml", "description: x\nentry: run.sh\n")
        let entry = try home.write("x/run.sh", "#!\necho hi\n")
        #expect(Doctor.check(Library.load(home: home.url)) == [
            Diagnostic(.warning, "has no shebang, so it runs with /bin/zsh", file: entry, automation: "x")
        ])
    }

    @Test(arguments: [false, true])
    func shellScriptWithoutShebang(executable: Bool) throws {
        let home = try TempHome()
        try home.write("x/manifest.yaml", "description: x\nentry: run.sh\n")
        let entry = try home.write("x/run.sh", "echo hi\n", executable: executable)
        #expect(Doctor.check(Library.load(home: home.url)) == [
            Diagnostic(.warning, "has no shebang, so it runs with /bin/zsh", file: entry, automation: "x")
        ])
    }
}
