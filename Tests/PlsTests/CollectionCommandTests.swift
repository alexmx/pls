import Foundation
import Testing

/// The collection commands against the built pls. Installed collections are set up by hand (a clone is just a folder
/// plus the record), so nothing touches the network; cloning and updating are tested in PlsCoreTests.
@Suite(.timeLimit(.minutes(1)))
struct CollectionCommandTests {
    private let pls: BuiltPls

    init() throws {
        self.pls = try BuiltPls()
        for (owner, word) in [("alexmx", "alex"), ("bob", "bob")] {
            let automations = pls.home.appending(path: "collections/\(owner)/tools/automations")
            try FileManager.default.createDirectory(at: automations, withIntermediateDirectories: true)
            try "#!/bin/zsh\n# @pls.description: Wifi from \(word)\necho \(word)\n"
                .write(to: automations.appending(path: "wifi.sh"), atomically: true, encoding: .utf8)
        }
        try #"[{"disabled": [], "source": "alexmx/tools"}, {"disabled": [], "source": "bob/tools"}]"#
            .write(to: pls.home.appending(path: "collections.json"), atomically: true, encoding: .utf8)
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
            .stdout == "alexmx/tools\n  on   wifi\n\nbob/tools\n  off  wifi\n")
        #expect(try await pls.run("collection", "enable", "wifi").status == 65)
        #expect(try await pls.run("collection", "enable", "bob/tools/wifi").status == 0)
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
        (["collection", "disable", "nothing"], 65)
    ])
    func mistakesHaveTheirExitCodes(arguments: [String], status: Int) async throws {
        #expect(try await Int(pls.run(arguments).status) == status)
    }
}
