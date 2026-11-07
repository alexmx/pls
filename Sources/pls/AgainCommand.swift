import ArgumentParser
import PlsCore

struct AgainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "again",
        abstract: "Run the last automation again with the same values.",
        discussion: """
        Values you gave last time are reused; defaults come from the automation as it is now. If it has gained a \
        required param since, you're asked for it.
        """
    )

    @OptionGroup var options: RunOptions

    @MainActor
    func run() async throws {
        let binding: Binding
        do {
            binding = try HistoryStore().replayLast(in: Library.loadDefault())
        } catch {
            switch error {
            case .noHistory:
                printError("pls: nothing to repeat yet; there are no runs in history")
                throw Exit.notFound
            case let .automationGone(id, hasProblems):
                printError(hasProblems
                    ? "pls: the last run was \(id), which has problems that keep it from loading; run `pls doctor`"
                    : "pls: the last run was \(id), which is no longer in your library")
                throw Exit.notFound
            case let .valueNoLongerFits(id, problem):
                printError("pls: can't repeat \(id): \(problem)")
                throw Exit.usage
            }
        }
        try await perform(binding, via: .again, options: options)
    }
}
