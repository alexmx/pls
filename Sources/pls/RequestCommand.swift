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

    /// Whether `arguments` are a request rather than a subcommand: they don't start with a subcommand's name or an
    /// option other than the ones a request takes.
    static func handles(_ arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        if first.hasPrefix("-") {
            return ["-y", "--yes", "--dry-run"].contains(first)
        }
        let commands = PlsCommand.configuration.subcommands.map { $0.configuration.commandName } + ["help"]
        return !commands.contains(first)
    }

    func run() async throws {
        let request = words.joined(separator: " ")
        guard !request.allSatisfy(\.isWhitespace) else { throw CleanExit.helpRequest(PlsCommand.self) }
        let binding: Binding?
        do {
            binding = try await NLResolver().resolve(request, in: Library.loadDefault())
        } catch {
            printError("pls: \(error)")
            throw Exit.modelUnavailable
        }
        guard let binding else {
            printError("pls: no automation matches \"\(request)\"")
            throw Exit.notFound
        }
        try perform(binding, via: .request, yes: yes, dryRun: dryRun)
    }
}
