import ArgumentParser
import Foundation
import PlsCore

/// The options of every command that runs an automation: `pls run`, `pls again` and requests. `Dispatch.runOptions`
/// lists their spellings for PlsCore.
struct RunOptions: ParsableArguments {
    @Flag(name: [.short, .long], help: "Don't ask before running.")
    var yes = false

    @Flag(help: "Show what would run, without running it.")
    var dryRun = false
}

/// What `pls run`, `pls again` and requests share once they have a binding: ask for what's missing, confirm if
/// the automation or the trigger wants it, then either preview (--dry-run) or run it (which records it in history).
func perform(_ binding: Binding, via trigger: HistoryEntry.Trigger, options: RunOptions) throws {
    let (yes, dryRun) = (options.yes, options.dryRun)
    var binding = binding
    let automation = binding.automation
    // A request is the model's guess, so it's always shown before it runs.
    let asksFirst = (automation.confirm || trigger == .request) && !yes && !dryRun

    // Without a terminal nothing can be asked: fail before announcing anything.
    if !dryRun, !Prompt.isInteractive {
        if !binding.missing.isEmpty {
            let names = binding.missing.map { "--\($0.name)" }.joined(separator: ", ")
            let message = switch trigger {
            case .run: "pls: missing \(names); give it on the command line (there's no terminal to ask in)"
            case .again:
                "pls: \(automation.id) now needs \(names), which the last run didn't have; use `pls run \(automation.id)`"
            case .request:
                "pls: the request doesn't give \(names) and there's no terminal to ask in; use `pls run \(automation.id)`"
            }
            printError(message)
            throw Exit.usage
        }
        if asksFirst {
            printError(trigger == .request
                ? "pls: a request asks before running; pass --yes to run it without a terminal"
                : "pls: \(automation.id) asks before running; pass --yes to run it without a terminal")
            throw Exit.usage
        }
    }
    // Say what's being repeated, unless the dry run or the confirm question is about to show the plan anyway.
    if trigger == .again, !dryRun, !asksFirst {
        let values = automation.params.compactMap { param in
            binding.values[param.name]
                .flatMap { $0.source == .repeated ? "\(param.name)=\(displayValue($0.value))" : nil }
        }
        printError((["↻ \(automation.id)"] + values).joined(separator: "  "))
    }
    if !dryRun {
        try Prompt.fillMissing(&binding)
    }
    if asksFirst {
        guard try Prompt.review(&binding) else { throw Exit.cancelled }
    }

    if dryRun {
        // A preview never asks: show what's missing instead of the command it can't complete yet.
        planLines(binding).forEach { print($0) }
        if binding.missing.isEmpty {
            invocationLines(Invocation(binding)).forEach { print($0) }
        } else {
            print("\n  pls would ask for \(binding.missing.map(\.name).joined(separator: ", ")) first.")
        }
        return
    }

    // From here the script owns the terminal: Ctrl-C goes to it (Runner resets it to the default there), and pls
    // ignores it so it can wait and exit with the script's status. Prompts above still quit on Ctrl-C.
    signal(SIGINT, SIG_IGN)
    signal(SIGQUIT, SIG_IGN)
    let outcome: Runner.Outcome
    do {
        outcome = try Runner.run(binding, via: trigger)
    } catch {
        printError("pls: \(error)")
        throw Exit.cannotRun
    }
    if let historyError = outcome.historyError {
        printError("pls: warning: \(historyError)")
    }
    if outcome.status != 0 {
        throw ExitCode(outcome.status)
    }
}
