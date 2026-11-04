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
        let binding: Binding
        do {
            binding = try HistoryStore().replayLast(in: Library.loadDefault())
        } catch {
            switch error {
            case .noHistory:
                printError("pls: nothing to repeat yet; there are no runs in history")
                throw Exit.notFound
            case let .automationGone(id, hasProblems):
                printError("pls: the last run was \(id), which is no longer in your library")
                if hasProblems {
                    printError("pls: \(id) has problems that keep it from loading; run `pls doctor`")
                }
                throw Exit.notFound
            case let .valueNoLongerFits(id, problem):
                printError("pls: can't repeat \(id): \(problem)")
                throw Exit.usage
            }
        }
        try perform(binding, via: .again, yes: yes, dryRun: dryRun)
    }
}
