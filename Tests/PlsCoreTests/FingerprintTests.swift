import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct FingerprintTests {
    private let home: TempHome

    init() throws {
        self.home = try TempHome()
        try home.write("one.sh", "#!/bin/zsh\necho one\n")
        try home.write("folder/manifest.yaml", "description: F\nentry: run.sh\n")
        try home.write("folder/run.sh", "#!/bin/zsh\n. ./helper.sh\n")
        try home.write("folder/helper.sh", "echo helper\n")
    }

    private func print(_ id: String) throws -> String {
        try Fingerprint.of(#require(Library.load(home: home.url).automation(id: id)))
    }

    @Test func theSameFilesGiveTheSameFingerprint() throws {
        #expect(try print("one") == print("one"))
        #expect(try print("one").hasPrefix("sha256:"))
    }

    @Test func editingTheScriptChangesIt() throws {
        let before = try print("one")
        try home.write("one.sh", "#!/bin/zsh\necho two\n")
        #expect(try print("one") != before)
    }

    /// Being executable decides whether pls runs the file itself or through its shebang.
    @Test func makingItExecutableChangesIt() throws {
        let before = try print("one")
        try home.write("one.sh", "#!/bin/zsh\necho one\n", executable: true)
        #expect(try print("one") != before)
    }

    /// Any file in a folder automation counts, not only its entry: a helper it runs, or a new file.
    @Test(arguments: ["folder/helper.sh", "folder/extra.txt"])
    func anyFileInAFolderChangesIt(file: String) throws {
        let before = try print("folder")
        try home.write(file, "rm -rf ~\n")
        #expect(try print("folder") != before)
    }

    @Test func renamingAFileInAFolderChangesIt() throws {
        let before = try print("folder")
        let folder = home.url.appending(path: "automations/folder")
        try FileManager.default.moveItem(
            at: folder.appending(path: "helper.sh"),
            to: folder.appending(path: "other.sh")
        )
        #expect(try print("folder") != before)
    }

    /// Opening the folder in Finder, to read the scripts, mustn't turn the automation off.
    @Test(arguments: [".DS_Store", "._run.sh"])
    func finderFilesDontCount(file: String) throws {
        let before = try print("folder")
        try home.write("folder/\(file)", "\u{0}\u{1}")
        #expect(try print("folder") == before)
    }

    /// Paths are relative to the automation's folder, so the same files give the same fingerprint wherever they are,
    /// even through a linked home (dotfiles managers make `~/.config` one).
    @Test func aLinkedHomeGivesTheSameFingerprint() throws {
        let linked = home.url.deletingLastPathComponent().appending(path: "linked-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: home.url)
        defer { try? FileManager.default.removeItem(at: linked) }
        let through = try #require(Library.load(home: linked).automation(id: "folder"))
        #expect(try Fingerprint.of(through) == print("folder"))
        #expect(through.files.map(through.relativePath(of:)) == ["helper.sh", "manifest.yaml", "run.sh"])
    }
}
