import Foundation
import Testing

/// The collection commands against the built pls. Installed collections are set up by hand (a clone is just a folder
/// plus the record), so nothing touches the network; cloning and updating are tested in PlsCoreTests.
@Suite(.timeLimit(.minutes(1)))
struct CollectionCommandTests {
    private let pls: BuiltPls

    init() async throws {
        self.pls = try BuiltPls()
        for (owner, word) in [("alexmx", "alex"), ("bob", "bob")] {
            try write("#!/bin/zsh\n# @pls.description: Wifi from \(word)\necho \(word)\n", to: "\(owner)/tools/wifi.sh")
        }
        // An older record, which said what was off: what's on when pls first reads it counts as approved.
        try #"[{"disabled": [], "source": "alexmx/tools"}, {"disabled": [], "source": "bob/tools"}]"#
            .write(to: pls.home.appending(path: "collections.json"), atomically: true, encoding: .utf8)
        #expect(try await pls.run("collection", "list")
            .stdout == "alexmx/tools\n  on       wifi\n\nbob/tools\n  on       wifi\n")
    }

    private func write(_ text: String, to path: String) throws {
        let parts = path.split(separator: "/", maxSplits: 2)
        let file = pls.home.appending(path: "collections/\(parts[0])/\(parts[1])/automations/\(parts[2])")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    /// A new automation in bob/tools, so there's something to review.
    private func addCleanup() throws {
        try write(
            "#!/bin/zsh\n# @pls.description: Clean up\nrm -rf ~/Library/Caches/thing\n",
            to: "bob/tools/cleanup.sh"
        )
    }

    /// Two collections share `wifi`, so the short id says which full names to use instead of guessing.
    @Test func aSharedIDNeedsTheFullName() async throws {
        let ambiguous = try await pls.run("run", "wifi")
        #expect(ambiguous.status == 65)
        #expect(ambiguous
            .stderr == "pls: several collections have wifi; use one of alexmx/tools/wifi, bob/tools/wifi\n")
        #expect(try await pls.run("run", "bob/tools/wifi").stdout == "bob\n")
    }

    @Test func disablingOneLeavesTheOtherTheShortID() async throws {
        #expect(try await pls.run("collection", "disable", "bob/tools/wifi").stdout == "Turned off bob/tools/wifi.\n")
        #expect(try await pls.run("run", "wifi").stdout == "alex\n")
        #expect(try await pls.run("collection", "list")
            .stdout == "alexmx/tools\n  on       wifi\n\nbob/tools\n  off      wifi\n")
        #expect(try await pls.run("collection", "enable", "wifi").status == 65)
    }

    /// Approving shows the script, so it needs a terminal; there it asks.
    @Test func enablingShowsTheScriptAndAsks() async throws {
        _ = try await pls.run("collection", "disable", "bob/tools/wifi")
        #expect(try await pls.run("collection", "enable", "bob/tools/wifi").status == 64)
        let enabled = try await pls.runInTerminal(
            ["collection", "enable", "bob/tools/wifi"], typing: "y\n", after: "Turn on wifi? [y/N]"
        )
        #expect(enabled.status == 0)
        #expect(enabled.output.contains("3 │ echo bob"))
        #expect(enabled.output.contains("Turned on bob/tools/wifi."))
        #expect(try await pls.run("run", "bob/tools/wifi").stdout == "bob\n")
    }

    /// An edit to an approved script turns it off until approved again, which leaves the short id to the other.
    @Test func aChangedScriptIsOff() async throws {
        try write("#!/bin/zsh\n# @pls.description: Wifi from bob\necho changed\n", to: "bob/tools/wifi.sh")
        #expect(try await pls.run("run", "wifi").stdout == "alex\n")
        #expect(try await pls.run("collection", "list").stdout.hasSuffix("bob/tools\n  changed  wifi\n"))
        #expect(try await pls.run("doctor").stdout.contains("changed since you approved it"))
    }

    /// Without a terminal nothing is turned on, but the warnings are still shown.
    @Test func withoutATerminalReviewOnlyWarns() async throws {
        try addCleanup()
        let review = try await pls.run("collection", "review")
        #expect(review.status == 0)
        #expect(review.stdout == """
        bob/tools: 1 automation is off until approved.
        Warnings:
          cleanup  deletes files (line 3: rm -rf ~/Library/Caches/thing)
        They stay off until approved: run `pls collection review bob/tools` in a terminal.
        
        """)
        #expect(try await pls.run("run", "cleanup").status == 65)
    }

    @Test(arguments: [
        (
            [(after: "[Y/n/a]", typing: "y\n"), (after: "Turn on cleanup? [y/N/a/q]", typing: "y\n")],
            "Turned on 1 of 1.",
            "on"
        ),
        (
            [(after: "[Y/n/a]", typing: "y\n"), (after: "Turn on cleanup? [y/N/a/q]", typing: "n\n")],
            "Turned on 0 of 1;",
            "off"
        ),
        ([(after: "[Y/n/a]", typing: "n\n")], "Left it off;", "off"),
        ([(after: "[Y/n/a]", typing: "a\n")], "Turned on all 1 without review.", "on")
    ])
    func reviewingAsks(answers: [(after: String, typing: String)], says: String, state: String) async throws {
        try addCleanup()
        let review = try await pls.runInTerminal(["collection", "review", "bob/tools"], answering: answers)
        #expect(review.status == 0)
        #expect(review.output.contains("deletes files"))
        #expect(review.output.contains(says), "\(review.output)")
        #expect(try await pls.run("collection", "list").stdout
            .contains("  \(state.padding(toLength: 7, withPad: " ", startingAt: 0))  cleanup\n"))
    }

    @Test func nothingToReview() async throws {
        #expect(try await pls.run("collection", "review")
            .stdout == "Nothing to review: every installed automation is approved.\n")
    }

    @Test func listShowsWhereAnAutomationComesFrom() async throws {
        let list = try await pls.run("list").stdout
        #expect(list.contains("alexmx/tools/wifi  shell  Wifi from alex  (alexmx/tools)"))
        #expect(try await pls.run("show", "bob/tools/wifi").stdout.contains("  from     bob/tools\n"))
    }

    @Test(arguments: [
        (["collection", "add", "gitlab.com/a/b"], 64),
        (["collection", "remove", "nobody/nothing"], 65),
        (["collection", "update", "nobody/nothing"], 65),
        (["collection", "review", "nobody/nothing"], 65),
        (["collection", "disable", "nothing"], 65)
    ])
    func mistakesHaveTheirExitCodes(arguments: [String], status: Int) async throws {
        #expect(try await Int(pls.run(arguments).status) == status)
    }
}
