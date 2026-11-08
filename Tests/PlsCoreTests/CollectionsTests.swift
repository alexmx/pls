import Foundation
@testable import PlsCore
import Subprocess
import Testing

/// Collections from local git repos standing in for GitHub, so nothing touches the network.
@Suite(.timeLimit(.minutes(1)))
struct CollectionsTests {
    private let home: TempHome
    private let store: CollectionStore
    /// Where the stand-in repos live: `<github>/<owner>/<repo>.git`, cloned from like `https://github.com/`.
    private let github: URL

    init() throws {
        self.home = try TempHome()
        self.github = home.url.appending(path: "github")
        self.store = CollectionStore(home: home.url, cloneBase: github.absoluteString)
    }

    /// Publishes `files` (paths under the repo) as `source`, or as a new commit on it.
    private func publish(_ source: String, _ files: [String: String], removing: [String] = []) async throws {
        let work = home.url.appending(path: "work/\(source)")
        let bare = github.appending(path: "\(source).git")
        if !FileManager.default.fileExists(atPath: bare.path) {
            try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
            try await git(["init", "--bare", "--quiet", "--initial-branch=main", bare.path])
            try await git(["clone", "--quiet", bare.path, work.path])
        }
        for (path, content) in files {
            let file = work.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: file, atomically: true, encoding: .utf8)
        }
        for path in removing {
            try FileManager.default.removeItem(at: work.appending(path: path))
        }
        try await git(["-C", work.path, "add", "-A"])
        try await git(["-C", work.path, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "--quiet", "-m", "x"])
        try await git(["-C", work.path, "push", "--quiet", "origin", "HEAD:main"])
    }

    private func git(_ arguments: [String]) async throws {
        let result = try await Subprocess.run(.name("git"), arguments: Arguments(arguments), output: .discarded)
        #expect(result.terminationStatus.isSuccess, "git \(arguments)")
    }

    private func automation(_ description: String) -> String {
        "#!/bin/zsh\n# @pls.description: \(description)\necho \(description)\n"
    }

    @Test(arguments: [
        ("alexmx/pls-automations", "alexmx/pls-automations", false),
        ("https://github.com/alexmx/pls-automations", "alexmx/pls-automations", false),
        ("github.com/alexmx/pls-automations.git", "alexmx/pls-automations", false),
        ("git@github.com:alexmx/pls-automations.git", "alexmx/pls-automations", true),
        ("ssh://git@github.com/alexmx/pls-automations", "alexmx/pls-automations", true)
    ])
    func addressesComeFromGitHub(argument: String, source: String, overSSH: Bool) {
        #expect(CollectionStore.address(from: argument) == CollectionStore.Address(source: source, overSSH: overSSH))
    }

    @Test(arguments: [
        "https://gitlab.com/alexmx/pls-automations", "git@gitlab.com:alexmx/tools.git", "pls-automations",
        "alexmx/pls/automations"
    ])
    func anythingElseIsRefused(argument: String) {
        #expect(CollectionStore.address(from: argument) == nil)
    }

    /// git runs ssh in batch mode, so a failing ssh (here one that fails at once, with no network) ends the add with a
    /// message instead of a prompt, and leaves nothing behind.
    @Test func aFailedSSHCloneSaysSoAndLeavesNothing() async throws {
        let store = CollectionStore(home: home.url, ssh: "/usr/bin/false")
        let error = await #expect(throws: CollectionStore.Failure.self) {
            try await store.add("alexmx/private-tools", overSSH: true)
        }
        #expect(error?.description.hasPrefix("couldn't get alexmx/private-tools over SSH;") == true)
        #expect(store.installed().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.url.appending(path: "collections/alexmx").path))
    }

    /// Adds `source` and approves everything in it, as answering "a" at the review does.
    private func addApproved(_ source: String) async throws {
        try await store.add(source)
        try store.approve(store.automations(of: source), in: source)
    }

    @Test func addingLeavesEverythingOff() async throws {
        try await publish(
            "alexmx/tools",
            ["automations/wifi.sh": automation("Wifi"), "automations/mute.sh": automation("Mute")]
        )
        #expect(try await store.add("alexmx/tools").map(\.id) == ["mute", "wifi"])
        #expect(Library.load(home: home.url).automations.isEmpty)
        #expect(store.pending(of: "alexmx/tools").map(\.id) == ["mute", "wifi"])
    }

    @Test func approvingTurnsOnExactlyThat() async throws {
        try await publish(
            "alexmx/tools",
            ["automations/wifi.sh": automation("Wifi"), "automations/mute.sh": automation("Mute")]
        )
        let pending = try await store.add("alexmx/tools")
        try store.approve(pending.filter { $0.id == "wifi" }, in: "alexmx/tools")
        let library = Library.load(home: home.url)
        #expect(library.automations.map(\.id) == ["wifi"])
        #expect(library.automations.allSatisfy { $0.collection == "alexmx/tools" })
        #expect(library.automation(id: "alexmx/tools/wifi")?.id == "wifi")
        #expect(store.pending(of: "alexmx/tools").map(\.id) == ["mute"])
    }

    @Test func aRepoWithoutAutomationsIsntInstalled() async throws {
        try await publish("alexmx/empty", ["README.md": "nothing here"])
        await #expect(throws: CollectionStore.Failure.self) { try await store.add("alexmx/empty") }
        #expect(store.installed().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.url.appending(path: "collections/alexmx").path))
    }

    @Test func aMissingRepoFailsWithoutAsking() async throws {
        let error = await #expect(throws: CollectionStore.Failure.self) { try await store.add("alexmx/nothing") }
        #expect(error?.description == "alexmx/nothing isn't a public GitHub repo")
        #expect(!FileManager.default.fileExists(atPath: home.url.appending(path: "collections/alexmx").path))
    }

    /// An update that changes an approved automation turns it off until it's approved again; new ones wait too.
    @Test func anUpdateTurnsOffWhatChangedUntilApprovedAgain() async throws {
        try await publish(
            "alexmx/tools",
            ["automations/wifi.sh": automation("Wifi"), "automations/mute.sh": automation("Mute")]
        )
        try await addApproved("alexmx/tools")
        try await publish(
            "alexmx/tools", ["automations/wifi.sh": automation("Wifi v2"), "automations/lock.sh": automation("Lock")],
            removing: ["automations/mute.sh"]
        )
        let report = try await store.update()
        #expect(report == [CollectionStore.Changes(
            source: "alexmx/tools",
            changed: ["wifi"],
            added: ["lock"],
            removed: ["mute"]
        )])
        let library = Library.load(home: home.url)
        #expect(library.automations.isEmpty)
        #expect(library.diagnostics.map(\.message)
            == ["changed since you approved it, so it's off; `pls collection review alexmx/tools` shows it"])
        #expect(store.pending(of: "alexmx/tools").map(\.id) == ["lock", "wifi"])
        try store.approve(store.pending(of: "alexmx/tools"), in: "alexmx/tools")
        #expect(Library.load(home: home.url).automation(id: "wifi")?.description == "Wifi v2")
        #expect(try await store.update() == [CollectionStore.Changes(source: "alexmx/tools")])
    }

    /// The fingerprint is of the files as they are, so editing the clone by hand turns an automation off too.
    @Test func editingTheCloneTurnsAnAutomationOff() async throws {
        try await publish("alexmx/tools", ["automations/wifi.sh": automation("Wifi")])
        try await addApproved("alexmx/tools")
        let file = store.folder(of: "alexmx/tools").appending(path: "automations/wifi.sh")
        try (automation("Wifi") + "rm -rf ~\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(Library.load(home: home.url).automations.isEmpty)
    }

    @Test func revokingTurnsItOff() async throws {
        try await publish(
            "alexmx/tools",
            ["automations/wifi.sh": automation("Wifi"), "automations/mute.sh": automation("Mute")]
        )
        try await addApproved("alexmx/tools")
        try store.revoke("mute", in: "alexmx/tools")
        #expect(Library.load(home: home.url).automations.map(\.id) == ["wifi"])
    }

    /// Records from before approvals said which ids were on; those count as approved, so nothing changes.
    @Test func anOlderRecordKeepsWhatWasOn() async throws {
        try await publish(
            "alexmx/tools",
            ["automations/wifi.sh": automation("Wifi"), "automations/mute.sh": automation("Mute")]
        )
        try await store.add("alexmx/tools")
        try #"[{"disabled": ["mute"], "source": "alexmx/tools"}]"#
            .write(to: home.url.appending(path: "collections.json"), atomically: true, encoding: .utf8)
        #expect(Library.load(home: home.url).automations.map(\.id) == ["wifi"])
        #expect(store.installed().first?.approved.keys.sorted() == ["wifi"])
    }

    /// Your own automation keeps the short id; the collection's is still there by its full name.
    @Test func yourOwnAutomationWinsTheShortID() async throws {
        try home.write("wifi.sh", automation("My wifi"))
        try await publish("alexmx/tools", ["automations/wifi.sh": automation("Their wifi")])
        try await addApproved("alexmx/tools")
        let library = Library.load(home: home.url)
        #expect(library.automation(id: "wifi")?.description == "My wifi")
        #expect(library.automation(id: "alexmx/tools/wifi")?.description == "Their wifi")
        #expect(library.ambiguousIDs.isEmpty)
    }

    /// Two collections with the same id: neither gets the short one, and the library can say which full names exist.
    @Test func anIDTwoCollectionsShareNeedsTheFullName() async throws {
        try await publish("alexmx/tools", ["automations/wifi.sh": automation("Alex wifi")])
        try await publish("bob/tools", ["automations/wifi.sh": automation("Bob wifi")])
        try await addApproved("alexmx/tools")
        try await addApproved("bob/tools")
        let library = Library.load(home: home.url)
        #expect(library.automation(id: "wifi") == nil)
        #expect(library.ambiguousIDs == ["wifi": ["alexmx/tools/wifi", "bob/tools/wifi"]])
        #expect(library.automation(id: "bob/tools/wifi")?.description == "Bob wifi")
    }

    @Test func removeLeavesTheLibraryAsItWas() async throws {
        try home.write("mine.sh", automation("Mine"))
        try await publish("alexmx/tools", ["automations/wifi.sh": automation("Wifi")])
        try await addApproved("alexmx/tools")
        try store.remove("alexmx/tools")
        #expect(store.installed().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.url.appending(path: "collections/alexmx").path))
        #expect(Library.load(home: home.url).automations.map(\.id) == ["mine"])
    }

    /// With a collection installed, having no automations of your own is normal.
    @Test func noFolderOfYourOwnIsFineWithACollection() async throws {
        try FileManager.default.removeItem(at: home.url.appending(path: "automations"))
        #expect(!Library.load(home: home.url).diagnostics.isEmpty)
        try await publish("alexmx/tools", ["automations/wifi.sh": automation("Wifi")])
        try await addApproved("alexmx/tools")
        let library = Library.load(home: home.url)
        #expect(library.diagnostics.isEmpty)
        #expect(library.automations.map(\.id) == ["wifi"])
    }

    @Test func aMissingCloneIsAnError() async throws {
        try await publish("alexmx/tools", ["automations/wifi.sh": automation("Wifi")])
        try await addApproved("alexmx/tools")
        try FileManager.default.removeItem(at: store.folder(of: "alexmx/tools"))
        let problems = Library.load(home: home.url).diagnostics
        #expect(problems
            .map(\.message) == ["the clone of alexmx/tools is missing; run `pls collection add alexmx/tools`"])
        #expect(problems.first?.severity == .error)
    }
}
