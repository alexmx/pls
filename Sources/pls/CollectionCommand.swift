import ArgumentParser
import PlsCore

struct CollectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "collection",
        abstract: "Install automations from GitHub repos and keep them up to date.",
        discussion: """
        A collection is a GitHub repo laid out like your library, with an automations folder. Nothing in it runs until \
        you approve it: installing and updating ask you to review new or changed automations, and a change to an \
        approved one turns it off until you review it again. A collection you trust, like your own, skips that: \
        everything in it turns on, and so does what updates add or change. Its automations load alongside yours: \
        an id that's taken is known by its full name, owner/repo/id, and your own automations keep theirs.
        """,
        subcommands: [
            List.self, Add.self, Update.self, Review.self, Enable.self, Disable.self, Trust.self, Untrust.self,
            Remove.self
        ],
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
                print((index == 0 ? "" : "\n") + collection.source + (collection.trusted ? "  (trusted)" : ""))
                for automation in store.automations(of: collection.source) {
                    print("  " + collection.state(of: automation).rawValue.padded(to: 7) + "  " + automation.id)
                }
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install a collection from GitHub, then review its automations.",
            discussion: "Nothing in it runs while installing, and nothing turns on until you approve it."
        )

        @Argument(help: "The GitHub repo: owner/repo, or git@github.com:owner/repo.git for a private one over SSH.")
        var source: String

        @Flag(help: "Trust it, like your own: turn on everything in it, and what updates add or change, unreviewed.")
        var trust = false

        @MainActor
        func run() async throws {
            let address = try githubAddress(source)
            let source = address.source
            let store = CollectionStore()
            let installing = !store.installed().contains { $0.source == source }
            let pending: [Automation]
            do throws(CollectionStore.Failure) {
                pending = try await Prompt.showingStatus(installing ? "Cloning \(source)…" : "Checking \(source)…") {
                    () async throws(CollectionStore.Failure) in try await store.add(source, overSSH: address.overSSH)
                }
            } catch {
                printError("pls: \(error)")
                throw ExitCode.failure
            }
            let total = store.automations(of: source).count
            if trust {
                printWarnings(pending)
                try failing { () throws(CollectionStore.Failure) in try store.trust(source) }
                print(installing
                    ? "Installed \(source), trusted: \(counted(total)) on."
                    : "Trusted \(source): \(counted(total)) on.")
                return
            }
            if installing {
                print(
                    "Installed \(source): \(counted(total)), all off. Their scripts run with your full user rights."
                )
            } else if pending.isEmpty {
                print("\(source) is installed, and everything in it is approved.")
                return
            } else {
                print("\(source) is installed; \(off(pending.count)) until approved.")
            }
            try review(pending, of: source, store: store)
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Pull the latest automations of installed collections, then review what's new or changed.",
            discussion: "Changed automations turn off until you approve them again, since they change what runs."
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
                // Asks about what's new or changed; what you left off before stays off quietly, for
                // `pls collection review`. A trusted collection's update already turned them on.
                guard let collection = store.installed().first(where: { $0.source == changes.source }) else { continue }
                let touched = Set(changes.added + changes.changed)
                if collection.trusted {
                    printWarnings(store.automations(of: changes.source).filter { touched.contains($0.id) })
                }
                let pending = store.automations(of: changes.source).filter { automation in
                    switch collection.state(of: automation) {
                    case .on: false
                    case .changed: true
                    case .off: touched.contains(automation.id)
                    }
                }
                if !pending.isEmpty {
                    print("\(off(pending.count)) until approved.")
                    try review(pending, of: changes.source, store: store)
                }
            }
        }
    }

    struct Review: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Review the automations that are off because they're new or changed, and turn on what you trust."
        )

        @Argument(help: "The collections to review (owner/repo); all when none is given.", completion: collections)
        var sources: [String] = []

        @MainActor
        func run() async throws {
            let store = CollectionStore()
            for source in sources {
                try requireInstalled(source, in: store)
            }
            var reviewed = false
            for collection in store.installed() where sources.isEmpty || sources.contains(collection.source) {
                let pending = store.pending(of: collection.source)
                guard !pending.isEmpty else { continue }
                reviewed = true
                print("\(collection.source): \(off(pending.count)) until approved.")
                try review(pending, of: collection.source, store: store)
            }
            if !reviewed {
                print("Nothing to review: every installed automation is approved.")
            }
        }
    }

    struct Enable: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Approve one automation of a collection, after showing it."
        )

        @Argument(help: "Its id, or owner/repo/id.", completion: automations)
        var automation: String

        @MainActor
        func run() async throws {
            let store = CollectionStore()
            let (source, automation) = try find(automation, in: store)
            guard Prompt.isInteractive else {
                printError("pls: approving shows the script and asks; run this in a terminal")
                throw Exit.usage
            }
            let fingerprint = CollectionStore.fingerprints(of: [automation])
            show(automation, ScriptWarnings.of(automation), position: source)
            guard Prompt.ask("  Turn on \(automation.id)? [y/N] ")?.trimmingCharacters(in: .whitespaces)
                .lowercased().hasPrefix("y") == true else {
                print("Left \(automation.id) off.")
                return
            }
            try failing { () throws(CollectionStore.Failure) in try store.approve(fingerprint, in: source) }
            print("Turned on \(source)/\(automation.id).")
        }
    }

    struct Disable: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Turn off a collection's automation; it stays off until you approve it again."
        )

        @Argument(help: "Its id, or owner/repo/id.", completion: automations)
        var automation: String

        func run() throws {
            let store = CollectionStore()
            let (source, automation) = try find(automation, in: store)
            try failing { () throws(CollectionStore.Failure) in try store.revoke(automation.id, in: source) }
            print("Turned off \(source)/\(automation.id).")
        }
    }

    struct Trust: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Trust a collection: turn on everything in it, and what updates add or change, without review.",
            discussion: """
            Like trusting a Homebrew tap. Its scripts run with your full user rights, so trust only collections you \
            control or know well; `pls collection untrust` stops it.
            """
        )

        @Argument(help: "The collection, owner/repo.", completion: collections)
        var source: String

        func run() throws {
            let store = CollectionStore()
            try requireInstalled(source, in: store)
            printWarnings(store.pending(of: source))
            try failing { () throws(CollectionStore.Failure) in try store.trust(source) }
            print(
                "Trusted \(source): \(counted(store.automations(of: source).count)) on, and updates turn on what they add or change."
            )
        }
    }

    struct Untrust: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop trusting a collection: what's on stays on, and what's new or changed waits for review again."
        )

        @Argument(help: "The collection, owner/repo.", completion: collections)
        var source: String

        func run() throws {
            let store = CollectionStore()
            try requireInstalled(source, in: store)
            try failing { () throws(CollectionStore.Failure) in try store.untrust(source) }
            print("\(source) is no longer trusted: what's on stays on, and what's new or changed waits for review.")
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
    return store.installed().flatMap { collection in
        store.automations(of: collection.source).map { "\(collection.source)/\($0.id)" }
    }
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

/// "1 automation" or "3 automations".
private func counted(_ count: Int) -> String {
    count == 1 ? "1 automation" : "\(count) automations"
}

/// "1 automation is off" or "3 automations are off".
private func off(_ count: Int) -> String {
    counted(count) + (count == 1 ? " is off" : " are off")
}

/// A collection's automation by id or owner/repo/id, with its collection; exit 65 if there's none or several.
private func find(_ reference: String, in store: CollectionStore) throws -> (source: String, automation: Automation) {
    let parts = reference.split(separator: "/").map(String.init)
    let sources = parts.count == 3 ? ["\(parts[0])/\(parts[1])"] : store.installed().map(\.source)
    let id = parts.last ?? reference
    if parts.count == 3 {
        try requireInstalled(sources[0], in: store)
    }
    let found = sources.compactMap { source in
        store.automations(of: source).first { $0.id == id }.map { (source, $0) }
    }
    guard found.count == 1, let match = found.first else {
        printError(found.isEmpty
            ? "pls: no installed collection has an automation \(id); `pls collection list` shows them"
            :
            "pls: several collections have \(id); use one of \(found.map { "\($0.0)/\(id)" }.joined(separator: ", "))")
        throw Exit.notFound
    }
    return match
}
