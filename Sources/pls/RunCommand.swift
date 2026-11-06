import ArgumentParser
import Foundation
import PlsCore

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run an automation.",
        discussion: """
        Give param values in declared order, or by name: `pls run compress-images ~/Pictures --quality 60`.
        Bool params also take --name / --no-name. Put -- before values that start with -.
        """
    )

    @Flag(name: [.short, .long], help: "Don't ask before running.")
    var yes = false

    @Flag(help: "Show what would run, without running it.")
    var dryRun = false

    @Argument(help: "The automation's id.", completion: runCompletion)
    var id: String

    @Argument(parsing: .allUnrecognized, help: "Param values.", completion: runCompletion)
    var values: [String] = []

    private static let runCompletion = CompletionKind.custom { words, current, _ in
        Completer.run(words, current: current, library: .loadDefault())
    }

    func run() throws {
        let library = Library.loadDefault()
        let automation: Automation
        do {
            automation = try library.require(id)
        } catch {
            // `pls run the backup` was probably meant as a request; command names win (SPEC §6).
            if !values.isEmpty, !library.leftOutIDs.contains(id) {
                printError(
                    "pls: to ask in plain words, quote the request: pls \"\((["run", id] + values).joined(separator: " "))\""
                )
            }
            throw error
        }
        let binding: Binding
        do {
            binding = try ParamBinder.bind(automation, arguments: values)
        } catch {
            printError("pls: \(error)")
            throw Exit.usage
        }
        try perform(binding, via: .run, yes: yes, dryRun: dryRun)
    }
}
