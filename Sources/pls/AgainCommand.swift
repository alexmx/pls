import ArgumentParser
import PlsCore

struct AgainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "again",
        abstract: "Run the last automation again with the same values.",
        discussion: """
        Values you gave last time are reused; defaults come from the automation as it is now. If it has gained a \
        required param since, you're asked for it.
        """
    )

    @Flag(name: [.short, .long], help: "Don't ask before running.")
    var yes = false

    @Flag(help: "Show what would run, without running it.")
    var dryRun = false

    func run() throws {
        guard let last = HistoryStore(file: HistoryStore.defaultFile()).recent(1).first else {
            printError("Nothing to repeat yet: no runs in history.")
            throw Exit.notFound
        }
        let library = Library.loadDefault()
        guard let automation = library.automation(id: last.id) else {
            printError("pls: the last run was \(last.id), which is no longer in your library.")
            if library.leftOutIDs.contains(last.id) {
                printError("It has problems that keep it from loading; run `pls doctor`.")
            }
            throw Exit.notFound
        }
        let binding: Binding
        do {
            binding = try ParamBinder.replay(last, for: automation)
        } catch {
            printError("pls: can't repeat \(last.id): \(error)")
            throw Exit.usage
        }
        // Say what's being repeated, unless the dry run or the confirm question is about to show the plan anyway.
        if !dryRun, !(automation.confirm && !yes) {
            let values = automation.params.compactMap { param in
                binding.values[param.name].flatMap { $0.source == .repeated ? "\(param.name)=\($0.value)" : nil }
            }
            printError((["↻ \(automation.id)"] + values).joined(separator: "  "))
        }
        try perform(binding, via: .again, yes: yes, dryRun: dryRun)
    }
}
