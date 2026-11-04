import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DoctorTests {
    @Test func healthyLibraryHasNoProblems() throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\n# @pls.description: A\n")
        try home.write("b.sh", "# @pls.description: B\n", executable: true)
        try home.write("c.applescript", "-- @pls.description: C\n")
        try home.write("d/manifest.yaml", "description: D\nentry: run.sh\n")
        try home.write("d/run.sh", "#!/bin/zsh\n")

        #expect(Doctor.check(Library.load(home: home.url), commandNames: ["list"]).isEmpty)
    }

    @Test func includesLoadingProblems() throws {
        let home = try TempHome()
        try home.write("bad.sh", "# @pls.param x: nope\n")
        let library = Library.load(home: home.url)
        #expect(Doctor.check(library, commandNames: []) == library.diagnostics)
        #expect(!library.diagnostics.isEmpty)
    }

    @Test func idThatIsACommand() throws {
        let home = try TempHome()
        let file = try home.write("list.sh", "#!/bin/zsh\n# @pls.description: x\n")
        #expect(Doctor.check(Library.load(home: home.url), commandNames: ["list"]) == [
            Diagnostic(
                .warning,
                "id list is also a command; run it with `pls run list`",
                file: file,
                automation: "list"
            )
        ])
    }

    @Test func missingDescription() throws {
        let home = try TempHome()
        let file = try home.write("x.sh", "#!/bin/zsh\n")
        #expect(Doctor.check(Library.load(home: home.url), commandNames: []) == [
            Diagnostic(
                .warning, "no description, so natural-language requests will never pick it", file: file, automation: "x"
            )
        ])
    }

    @Test func folderProblemsPointAtTheManifest() throws {
        let home = try TempHome()
        let manifest = try home.write("x/manifest.yaml", "entry: run.sh\nicon: fire\n")
        try home.write("x/run.sh", "#!/bin/zsh\n")
        let files = Doctor.check(Library.load(home: home.url), commandNames: []).map(\.file)
        #expect(files == [manifest, manifest])
    }

    @Test func nonExecutableShellScriptWithoutShebang() throws {
        let home = try TempHome()
        try home.write("x/manifest.yaml", "description: x\nentry: run.sh\n")
        let entry = try home.write("x/run.sh", "echo hi\n")
        #expect(Doctor.check(Library.load(home: home.url), commandNames: []) == [
            Diagnostic(
                .warning, "not executable and has no shebang, so it will run with /bin/zsh", file: entry,
                automation: "x"
            )
        ])
    }
}
