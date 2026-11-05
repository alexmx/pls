import ArgumentParser
import PlsCore

/// `pls "<request>"`: the on-device model picks an automation and fills its values; the plan is shown before it runs.
struct RequestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pls",
        abstract: "Run what a request in plain words asks for."
    )

    @Flag(name: [.short, .long], help: "Don't ask before running.")
    var yes = false

    @Flag(help: "Show what would run, without running it.")
    var dryRun = false

    @Argument(parsing: .allUnrecognized, help: "The request; quoting it is optional.")
    var words: [String] = []

    /// On the main actor, so after asking the model it resumes on the main thread, where every other command prompts
    /// and runs the script. Prompting from one of Swift's background threads, Ctrl-C and SIGTERM didn't end pls.
    @MainActor
    func run() async throws {
        let request = words.joined(separator: " ")
        // Only options, e.g. `pls --yes`: show the main help, not this command's.
        guard !request.allSatisfy(\.isWhitespace) else {
            printError(PlsCommand.helpMessage())
            throw Exit.usage
        }
        let library = Library.loadDefault()
        let binding: Binding?
        do {
            binding = try await Prompt.showingStatus("Thinking…") { () async throws(NLResolver.ModelError) in
                try await NLResolver().resolve(request, in: library)
            }
        } catch let .unavailable(reason) {
            binding = try pickByWords(request, in: library, because: reason)
        } catch let .failed(reason) {
            printError("pls: \(reason)")
            throw ExitCode.failure
        }
        guard let binding else {
            printError("pls: no automation matches \"\(request)\"")
            let closest = FuzzyMatcher.closest(to: request, in: library.automations)
            if !closest.isEmpty {
                printError("Closest:")
                table(closest.map { [$0.id, $0.description ?? ""] }, indent: "  ").forEach(printError)
            }
            throw Exit.notFound
        }
        try perform(binding, via: .request, yes: yes, dryRun: dryRun)
    }

    /// Without the model (SPEC §7): offers the closest automations by shared words and returns the one picked, with
    /// its defaults; `perform` then asks for what's missing and shows the plan. Exit 69 if none is picked.
    private func pickByWords(_ request: String, in library: Library, because reason: String) throws -> Binding {
        printError("pls: \(reason); matching by words instead")
        let closest = FuzzyMatcher.closest(to: request, in: library.automations)
        guard !closest.isEmpty else {
            printError("pls: no automation shares a word with \"\(request)\"")
            throw Exit.modelUnavailable
        }
        let rows = closest.enumerated().map { ["\($0.offset + 1)", $0.element.id, $0.element.description ?? ""] }
        table(rows, indent: "  ").forEach(printError)
        guard !dryRun, Prompt.isInteractive else {
            printError(dryRun
                ? "pls would ask which one to run."
                : "pls: no terminal to choose in; run one with `pls run <id>`")
            throw Exit.modelUnavailable
        }
        guard let index = try Prompt.choose(among: closest.count) else { throw Exit.modelUnavailable }
        return ParamBinder.bind(closest[index], request: request, values: [:])
    }
}
