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

    @Argument(help: "The automation's id.")
    var id: String

    @Argument(parsing: .allUnrecognized, help: "Param values.")
    var values: [String] = []

    func run() throws {
        let automation = try Library.loadDefault().require(id)
        var binding: Binding
        do {
            binding = try ParamBinder.bind(automation, arguments: values)
        } catch {
            printError("pls: \(error)")
            throw Exit.usage
        }

        if !binding.missing.isEmpty, !dryRun {
            guard Prompt.isInteractive else {
                let names = binding.missing.map { "--\($0.name)" }.joined(separator: ", ")
                printError("pls: missing \(names); give it on the command line (there's no terminal to ask in)")
                throw Exit.usage
            }
            try Prompt.fillMissing(&binding)
        }
        if automation.confirm, !yes, !dryRun {
            guard Prompt.isInteractive else {
                printError("pls: \(automation.id) asks before running; pass --yes to run it without a terminal")
                throw Exit.usage
            }
            guard Prompt.confirm(binding) else { throw Exit.cancelled }
        }

        let invocation = Invocation(binding)
        if dryRun {
            // A preview never asks: show what's missing instead of the command it can't complete yet.
            printPlan(binding)
            if binding.missing.isEmpty {
                printInvocation(invocation)
            } else {
                print("\n  pls would ask for \(binding.missing.map(\.name).joined(separator: ", ")) first.")
            }
            return
        }

        // From here the script owns the terminal: Ctrl-C goes to it (Runner resets it to the default there), and pls
        // ignores it so it can wait and exit with the script's status. Prompts above still quit on Ctrl-C.
        signal(SIGINT, SIG_IGN)
        signal(SIGQUIT, SIG_IGN)
        let status: Int32
        do {
            status = try Runner.run(invocation)
        } catch {
            printError("pls: \(error)")
            throw Exit.cannotRun
        }
        if status != 0 {
            throw ExitCode(status)
        }
    }
}
