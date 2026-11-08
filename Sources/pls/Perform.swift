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

/// What `pls run`, `pls again` and requests share once they have a binding: ask for what's missing, confirm if the
/// automation or the trigger wants it, then show a dry run, start it in the background, or run it in the terminal
/// (the last two record it in history).
@MainActor
func perform(_ binding: Binding, via trigger: HistoryEntry.Trigger, options: RunOptions) async throws {
    let (yes, dryRun) = (options.yes, options.dryRun)
    var binding = binding
    let automation = binding.automation
    // A request is the model's guess, so it's always shown before it runs. An automation can ask only for some of a
    // param's choices, so this depends on the values, which prompting can still complete.
    func asksFirst(_ binding: Binding) -> Bool {
        (automation.confirm.asks(for: binding) || trigger == .request) && !yes && !dryRun
    }

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
        if asksFirst(binding) {
            printError(trigger == .request
                ? "pls: a request asks before running; pass --yes to run it without a terminal"
                : "pls: \(automation.id) asks before running; pass --yes to run it without a terminal")
            throw Exit.usage
        }
    }
    // Say what's being repeated, unless the dry run or the confirm question is about to show the plan anyway.
    if trigger == .again, !dryRun, !asksFirst(binding) {
        let values = automation.params.compactMap { param in
            binding.values[param.name]
                .flatMap { $0.source == .repeated ? "\(param.name)=\(displayValue($0.value))" : nil }
        }
        printError((["↻ \(automation.id)"] + values).joined(separator: "  "))
    }
    if !dryRun {
        try Prompt.fillMissing(&binding)
    }
    if asksFirst(binding) {
        guard try await Prompt.review(&binding, preview: previewOutput) else { throw Exit.cancelled }
    }

    if dryRun {
        await showDryRun(binding)
    } else if automation.background {
        try await start(binding, via: trigger)
    } else {
        try await runInTerminal(binding, via: trigger)
    }
}

/// `--dry-run`: the plan, and with complete values the command, how it runs and its preview. It never asks, so it
/// shows what's missing instead of the command it can't complete yet.
@MainActor
private func showDryRun(_ binding: Binding) async {
    planLines(binding, style: Style(for: STDOUT_FILENO)).forEach { print($0) }
    guard binding.missing.isEmpty else {
        print("\n  pls would ask for \(binding.missing.map(\.name).joined(separator: ", ")) first.")
        return
    }
    invocationLines(Invocation(binding)).forEach { print($0) }
    if binding.automation.background {
        print("  runs in the background")
    }
    await previewOutput(binding).forEach { print($0) }
}

/// What an automation that supports it says it would do (`@pls.preview`); only complete values can be previewed.
@MainActor
private func previewOutput(_ binding: Binding) async -> [String] {
    guard binding.automation.preview, binding.missing.isEmpty else { return [] }
    do {
        let (status, output) = try await Runner.preview(binding)
        return previewLines(status: status, output: output)
    } catch {
        return ["", "  preview: \(error)"]
    }
}

/// Runs the script with the terminal, recording it in history, and exits with its status.
@MainActor
private func runInTerminal(_ binding: Binding, via trigger: HistoryEntry.Trigger) async throws {
    // From here the script owns the terminal: Ctrl-C goes to it (Runner resets it to the default there), and pls
    // ignores it so it can wait and exit with the script's status. Prompts above still quit on Ctrl-C.
    signal(SIGINT, SIG_IGN)
    signal(SIGQUIT, SIG_IGN)
    let outcome: Runner.Outcome
    do {
        outcome = try await Runner.run(binding, via: trigger)
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

/// Starts a background automation and says what it printed first and how to stop it.
@MainActor
private func start(_ binding: Binding, via trigger: HistoryEntry.Trigger) async throws {
    let started: Runner.Started
    do {
        started = try await Runner.start(binding, via: trigger)
    } catch {
        printError("pls: \(error)")
        throw Exit.cannotRun
    }
    if !started.output.isEmpty {
        print(started.output)
        // Before the hint below, which goes to unbuffered stderr.
        fflush(stdout)
    }
    let id = binding.automation.id
    if started.job.isRunning {
        printError("Running in the background; `pls jobs stop \(id)` ends it.")
    }
    if let historyError = started.historyError {
        printError("pls: warning: \(historyError)")
    }
}
