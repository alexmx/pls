import ArgumentParser
import PlsCore

struct CollectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collection",
        abstract: "Install automations from GitHub repos and keep them up to date.",
        discussion: """
        A collection is a GitHub repo laid out like your library, with an automations folder. Its automations load \
        alongside yours: an id that's taken is known by its full name, owner/repo/id, and your own automations keep \
        theirs.
        """,
        subcommands: [List.self, Add.self, Update.self, Enable.self, Disable.self, Remove.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List installed collections and their automations.")

        func run() {
            let store = CollectionStore()
            let collections = store.installed()
            guard !collections.isEmpty else {
                print("No collections installed; add one with `pls collection add <owner/repo>`.")
                return
            }
            for (index, collection) in collections.enumerated() {
                print((index == 0 ? "" : "\n") + collection.source)
                // A fixed width, so every collection's ids line up.
                for id in store.automationIDs(of: collection.source) {
                    print("  " + (collection.isEnabled(id) ? "on" : "off").padded(to: 3) + "  " + id)
                }
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install a collection from GitHub, or change which of its automations are on.",
            discussion: "Nothing in it runs while installing. Running add again changes the selection."
        )

        @Argument(help: "The GitHub repo: owner/repo, or git@github.com:owner/repo.git for a private one over SSH.")
        var source: String

        @Option(help: "Turn on only these automations (comma-separated ids); otherwise all, and new ones as they come.")
        var only: String?

        @MainActor
        func run() async throws {
            let address = try githubAddress(source)
            let source = address.source
            let only = only.map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            let store = CollectionStore()
            let installing = !store.installed().contains { $0.source == source }
            let ids: [String]
            do throws(CollectionStore.Failure) {
                ids = try await Prompt.showingStatus(installing ? "Cloning \(source)…" : "Checking \(source)…") {
                    () async throws(CollectionStore.Failure) in
                    try await store.add(source, overSSH: address.overSSH, only: only)
                }
            } catch {
                printError("pls: \(error)")
                throw ExitCode.failure
            }
            let verb = installing ? "Installed" : "Updated"
            print(only
                .map { "\(verb) \(source): \($0.count) of \(ids.count) automations on (\($0.joined(separator: ", ")))."
                }
                ?? "\(verb) \(source): all \(ids.count) automations on.")
            let problems = Library.loadDefault().diagnostics.filter {
                $0.file?.path.hasPrefix(store.folder(of: source).path) == true
            }
            if !problems.isEmpty {
                printError(
                    "pls: warning: \(problems.count) problem\(problems.count == 1 ? "" : "s") in them; run `pls doctor`"
                )
            }
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Pull the latest automations of installed collections.",
            discussion: "Updates change scripts that will run, so this lists every automation that changed."
        )

        @Argument(help: "The collections to update (owner/repo); all when none is given.", completion: collections)
        var sources: [String] = []

        @MainActor
        func run() async throws {
            let store = CollectionStore()
            for source in sources {
                try requireInstalled(source, in: store)
            }
            let report: [CollectionStore.Changes]
            do throws(CollectionStore.Failure) {
                report = try await Prompt.showingStatus("Updating…") { () async throws(CollectionStore.Failure) in
                    try await store.update(sources)
                }
            } catch {
                printError("pls: \(error)")
                throw ExitCode.failure
            }
            guard !report.isEmpty else {
                print("No collections installed; add one with `pls collection add <owner/repo>`.")
                return
            }
            for changes in report {
                var parts: [String] = []
                if !changes.changed.isEmpty {
                    parts.append("changed \(changes.changed.joined(separator: ", "))")
                }
                if !changes.added.isEmpty {
                    parts.append("new \(changes.added.joined(separator: ", "))")
                }
                if !changes.removed.isEmpty {
                    parts.append("removed \(changes.removed.joined(separator: ", "))")
                }
                print("\(changes.source): " + (parts.isEmpty ? "up to date" : parts.joined(separator: "; ")))
            }
        }
    }

    struct Enable: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn a collection's automation back on.")

        @Argument(help: "Its id, or owner/repo/id.", completion: automations)
        var automation: String

        func run() throws {
            try setEnabled(true, automation)
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Turn off a collection's automation; it stays off across updates."
        )

        @Argument(help: "Its id, or owner/repo/id.", completion: automations)
        var automation: String

        func run() throws {
            try setEnabled(false, automation)
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Uninstall a collection.")

        @Argument(help: "The collection, owner/repo.", completion: collections)
        var source: String

        func run() throws {
            let store = CollectionStore()
            try requireInstalled(source, in: store)
            try failing { () throws(CollectionStore.Failure) in try store.remove(source) }
            print("Removed \(source).")
        }
    }
}

// MARK: shared

private let collections = CompletionKind.custom { _, _, _ in CollectionStore().installed().map(\.source) }

/// Every installed collection's automations by full name, for enable and disable.
private let automations = CompletionKind.custom { _, _, _ in
    let store = CollectionStore()
    return store.installed()
        .flatMap { collection in store.automationIDs(of: collection.source).map { "\(collection.source)/\($0)" } }
}

/// The repo and how to reach it from what was typed, or exit 64.
private func githubAddress(_ argument: String) throws -> CollectionStore.Address {
    guard let address = CollectionStore.address(from: argument) else {
        printError("pls: collections come from GitHub; give owner/repo, or git@github.com:owner/repo.git over SSH")
        throw Exit.usage
    }
    return address
}

private func requireInstalled(_ source: String, in store: CollectionStore) throws {
    guard store.installed().contains(where: { $0.source == source }) else {
        printError("pls: no collection \(source) is installed; `pls collection list` shows them")
        throw Exit.notFound
    }
}

/// `body`, with a collection failure printed and turned into exit 1.
private func failing<T>(_ body: () throws(CollectionStore.Failure) -> T) throws -> T {
    do {
        return try body()
    } catch {
        printError("pls: \(error)")
        throw ExitCode.failure
    }
}

/// Turns an automation, given by id or owner/repo/id, on or off in its collection.
private func setEnabled(_ enabled: Bool, _ automation: String) throws {
    let store = CollectionStore()
    let parts = automation.split(separator: "/").map(String.init)
    let owners: [String]
    let id: String
    if parts.count == 3 {
        owners = ["\(parts[0])/\(parts[1])"]
        id = parts[2]
        try requireInstalled(owners[0], in: store)
    } else {
        id = automation
        owners = store.installed().map(\.source).filter { store.automationIDs(of: $0).contains(id) }
    }
    guard owners.count == 1, let source = owners.first else {
        printError(owners.isEmpty
            ? "pls: no installed collection has an automation \(id); `pls collection list` shows them"
            : "pls: several collections have \(id); use one of \(owners.map { "\($0)/\(id)" }.joined(separator: ", "))")
        throw Exit.notFound
    }
    try failing { () throws(CollectionStore.Failure) in try store.setEnabled(enabled, id: id, in: source) }
    print("Turned \(enabled ? "on" : "off") \(source)/\(id).")
}
