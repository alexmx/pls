import ArgumentParser
import Foundation
import PlsCore

/// What `pls run` and `pls again` share once they have a binding: ask for what's missing, confirm if the
/// automation wants it, then either preview (--dry-run) or run and record the run in history.
func perform(_ binding: Binding, via trigger: HistoryEntry.Trigger, yes: Bool, dryRun: Bool) throws {
    var binding = binding
    let automation = binding.automation
    if !binding.missing.isEmpty, !dryRun {
        guard Prompt.isInteractive else {
            let names = binding.missing.map { "--\($0.name)" }.joined(separator: ", ")
            printError(trigger == .again
                ? "pls: \(automation.id) now needs \(names), which the last run didn't have; use `pls run \(automation.id)`"
                : "pls: missing \(names); give it on the command line (there's no terminal to ask in)")
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
    let started = Date()
    let status: Int32
    do {
        status = try Runner.run(invocation)
    } catch {
        printError("pls: \(error)")
        throw Exit.cannotRun
    }

    let entry = HistoryEntry(
        binding, via: trigger, exit: status, seconds: Date().timeIntervalSince(started), at: started
    )
    do {
        try HistoryStore(file: HistoryStore.defaultFile()).append(entry)
    } catch {
        printError("pls: warning: \(error)")
    }
    if status != 0 {
        throw ExitCode(status)
    }
}
