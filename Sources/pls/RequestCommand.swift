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
    /// and runs the script. On another thread, Ctrl-C at a prompt didn't end pls.
    @MainActor
    func run() async throws {
        let request = words.joined(separator: " ")
        // Only options, e.g. `pls --yes`: show the main help, not this command's.
        guard !request.allSatisfy(\.isWhitespace) else {
            printError(PlsCommand.helpMessage())
            throw Exit.usage
        }
        let binding: Binding?
        do {
            binding = try await Prompt.showingStatus("Thinking…") { () async throws(NLResolver.ModelError) in
                try await NLResolver().resolve(request, in: Library.loadDefault())
            }
        } catch {
            printError("pls: \(error)")
            switch error {
            case .unavailable: throw Exit.modelUnavailable
            case .failed: throw ExitCode.failure
            }
        }
        guard let binding else {
            printError("pls: no automation matches \"\(request)\"")
            throw Exit.notFound
        }
        try perform(binding, via: .request, yes: yes, dryRun: dryRun)
    }
}
