import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LibraryTests {
    @Test func loadsBothFormats() throws {
        let home = try TempHome()
        let script = try home.write("kill-port.sh", "#!/bin/zsh\n# @pls.description: Kill a port\nlsof\n")
        let appleScript = try home.write("dark-mode.applescript", "-- @pls.description: Dark mode\non run\nend run\n")
        try home.write("compress-images/manifest.yaml", "description: Compress\nentry: run.sh\n")
        let entry = try home.write("compress-images/run.sh", "#!/bin/zsh\n")
        try home.write("compiled/manifest.yaml", "entry: script.scpt\n")
        try home.write("compiled/script.scpt", "binary")

        let library = Library.load(home: home.url)

        #expect(library.diagnostics.isEmpty)
        #expect(library.automations.map(\.id) == ["compiled", "compress-images", "dark-mode", "kill-port"])
        #expect(library.automation(id: "kill-port")?.kind == .shell)
        #expect(library.automation(id: "kill-port")?.script == script)
        #expect(library.automation(id: "kill-port")?.description == "Kill a port")
        #expect(library.automation(id: "dark-mode")?.kind == .applescript)
        #expect(library.automation(id: "dark-mode")?.script == appleScript)
        #expect(library.automation(id: "compress-images")?.script == entry)
        #expect(library.automation(id: "compress-images")?.description == "Compress")
        #expect(library.automation(id: "compiled")?.kind == .applescript)
    }

    @Test func manifestKindOverridesTheEntryExtension() throws {
        let home = try TempHome()
        try home.write("x/manifest.yaml", "entry: run\nkind: applescript\n")
        try home.write("x/run", "")
        #expect(Library.load(home: home.url).automation(id: "x")?.kind == .applescript)
    }

    @Test func missingFolderIsAnEmptyLibraryWithAWarning() {
        let library = Library.load(home: URL(filePath: "/nonexistent/pls-home"))
        #expect(library.automations.isEmpty)
        #expect(library.diagnostics.map(\.severity) == [.warning])
        #expect(library.diagnostics.first?.file == library.automationsDirectory)
    }

    @Test func unreadableFolderIsAnError() throws {
        let home = try TempHome()
        try FileManager.default.removeItem(at: home.url.appending(path: "automations"))
        try "not a folder".write(to: home.url.appending(path: "automations"), atomically: true, encoding: .utf8)
        let library = Library.load(home: home.url)
        #expect(library.diagnostics.map(\.severity) == [.error])
    }

    @Test func skipsHiddenFiles() throws {
        let home = try TempHome()
        try home.write(".DS_Store", "junk")
        #expect(Library.load(home: home.url).automations.isEmpty)
    }

    @Test func automationWithAnErrorIsLeftOutAndReportedWithItsFile() throws {
        let home = try TempHome()
        let file = try home.write("bad.sh", "# @pls.param size: huge\n")
        try home.write("good.sh", "")

        let library = Library.load(home: home.url)

        #expect(library.automations.map(\.id) == ["good"])
        #expect(library.diagnostics.map(\.file) == [file])
        #expect(library.diagnostics.map(\.line) == [1])
    }

    @Test func warningsKeepTheAutomation() throws {
        let home = try TempHome()
        try home.write("x.sh", "# @pls.icon: fire\n")
        let library = Library.load(home: home.url)
        #expect(library.automations.map(\.id) == ["x"])
        #expect(library.diagnostics.map(\.severity) == [.warning])
    }

    @Test func duplicateIDKeepsTheFirstAndReportsTheSecond() throws {
        let home = try TempHome()
        try home.write("kill-port.bash", "")
        let second = try home.write("kill-port.sh", "")

        let library = Library.load(home: home.url)

        #expect(library.automations.map(\.script.lastPathComponent) == ["kill-port.bash"])
        #expect(library.diagnostics == [
            Diagnostic(.error, "id kill-port is already used by kill-port.bash", file: second)
        ])
    }

    @Test(arguments: ["Kill Port.sh", "kill_port.sh", "-x.sh"])
    func invalidIDIsAnError(filename: String) throws {
        let home = try TempHome()
        try home.write(filename, "")
        let library = Library.load(home: home.url)
        #expect(library.automations.isEmpty)
        #expect(library.diagnostics.first?.message.contains("must be lowercase kebab-case") == true)
    }

    @Test func folderErrors() throws {
        let home = try TempHome()
        try home.mkdir("no-manifest")
        try home.write("no-entry-key/manifest.yaml", "name: x\n")
        try home.write("missing-entry/manifest.yaml", "entry: run.sh\n")
        try home.write("standalone.scpt", "binary")

        let library = Library.load(home: home.url)

        #expect(library.automations.isEmpty)
        let found = library.diagnostics.map { "\($0.severity.rawValue): \($0.file!.lastPathComponent): \($0.message)" }
        #expect(found == [
            "error: manifest.yaml: entry file run.sh doesn't exist",
            "error: manifest.yaml: missing entry (the script file to run)",
            "warning: no-manifest: folder has no manifest.yaml, so it's ignored",
            "error: standalone.scpt: compiled .scpt files can't carry a header; put it in a folder with a manifest.yaml"
        ])
    }

    @Test func homeComesFromPlsHomeThenXDGConfigHome() {
        let both = ["PLS_HOME": "/tmp/p", "XDG_CONFIG_HOME": "/tmp/config"]
        #expect(Library.defaultHome(environment: both).path == "/tmp/p")
        #expect(Library.defaultHome(environment: ["XDG_CONFIG_HOME": "/tmp/config"]).path == "/tmp/config/pls")
        #expect(Library.defaultHome(environment: [:]).path.hasSuffix("/.config/pls"))
    }
}
