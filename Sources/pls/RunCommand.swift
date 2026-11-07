import ArgumentParser
import Foundation
import PlsCore

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run an automation.",
        discussion: """
        Give param values in declared order, or by name: `pls run compress-images ~/Pictures --quality 60`.
        Bool params also take --name / --no-name. Put -- before values that start with -.
        """
    )

    @OptionGroup var options: RunOptions

    @Argument(help: "The automation's id.", completion: runCompletion)
    var id: String

    @Argument(parsing: .allUnrecognized, help: "Param values.", completion: runCompletion)
    var values: [String] = []

    private static let runCompletion = CompletionKind.custom { words, current, _ in
        CompletionCommand.words(for: Completer.runArguments(words, current: current, library: .loadDefault()))
    }

    @MainActor
    func run() async throws {
        let library = Library.loadDefault()
        let automation: Automation
        do {
            automation = try library.require(id)
        } catch {
            // `pls run the backup` was probably meant as a request; command names win.
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
        try await perform(binding, via: .run, options: options)
    }
}
