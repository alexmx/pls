import ArgumentParser
import Foundation
import PlsCore

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run an automation.",
        discussion: """
        Give param values in declared order, or by name: `pls run compress-images ~/Pictures --quality 60`.
        Bool params also take --name / --no-name. Use -- before values that start with --.
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
        let binding: Binding
        do {
            binding = try ParamBinder.bind(automation, arguments: values)
        } catch {
            printError("pls: \(error)")
            throw Exit.usage
        }
        if !binding.missing.isEmpty {
            printError("pls: missing \(binding.missing.map { "--\($0.name)" }.joined(separator: ", "))")
            throw Exit.usage
        }

        let invocation = Invocation(binding)
        if dryRun {
            printPlan(binding)
            printInvocation(invocation)
            return
        }

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
