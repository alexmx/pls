import ArgumentParser
import PlsCore

/// Asks you to review a collection's automations that aren't approved (new, or changed since), with their warnings
/// first. You can go through them one by one, leave them off, or turn them all on unread, which is on you. Without a
/// terminal they stay off.
@MainActor
func review(_ pending: [Automation], of source: String, store: CollectionStore) throws {
    guard !pending.isEmpty else { return }
    let warned = pending.map { ($0, ScriptWarnings.of($0)) }
    printWarnings(warned)
    guard Prompt.isInteractive else {
        print("They stay off until approved: run `pls collection review \(source)` in a terminal.")
        return
    }
    let count = pending.count == 1 ? "it" : "them"
    switch Prompt.ask("Review \(count) before turning \(count) on? [Y/n/a] ")?.trimmingCharacters(in: .whitespaces)
        .lowercased() {
    case nil, "n", "no":
        print("Left \(count) off; `pls collection review \(source)` turns \(count) on later.")
    case "a", "all":
        try approve(CollectionStore.fingerprints(of: pending), of: source, store: store)
        print("Turned on all \(pending.count) without review.")
    default:
        var approved = 0
        walk: for (index, (automation, warnings)) in warned.enumerated() {
            let fingerprint = CollectionStore.fingerprints(of: [automation])
            show(automation, warnings, position: "\(index + 1)/\(warned.count)")
            while true {
                switch Prompt.ask("  Turn on \(automation.id)? [y/N/a/q] ")?.trimmingCharacters(in: .whitespaces)
                    .lowercased() {
                case "y", "yes":
                    try approve(fingerprint, of: source, store: store)
                    approved += 1
                case "", "n", "no":
                    break
                case "a", "all":
                    let rest = Array(warned[index...].map(\.0))
                    // This one as shown; the rest as they are, unread.
                    try approve(
                        CollectionStore.fingerprints(of: rest).merging(fingerprint) { $1 }, of: source, store: store
                    )
                    approved += rest.count
                    break walk
                case nil, "q", "quit":
                    break walk
                default:
                    continue
                }
                break
            }
        }
        let left = pending.count - approved
        print("\nTurned on \(approved) of \(pending.count)"
            + (left == 0 ? "." : "; the rest stay off until `pls collection review \(source)`."))
    }
}

/// The warnings of `automations`, one per line under a heading; nothing when there are none.
func printWarnings(_ automations: [Automation]) {
    printWarnings(automations.map { ($0, ScriptWarnings.of($0)) })
}

private func printWarnings(_ warned: [(Automation, [ScriptWarning])]) {
    let flagged = warned.filter { !$0.1.isEmpty }
    guard !flagged.isEmpty else { return }
    print("Warnings:")
    let width = flagged.map(\.0.id.count).max() ?? 0
    for (automation, warnings) in flagged {
        for warning in warnings {
            print("  " + automation.id.padded(to: width) + "  " + describe(warning, in: automation))
        }
    }
}

/// One automation as you review it: what it says it does, its warnings, then every line of every file, numbered.
@MainActor
func show(_ automation: Automation, _ warnings: [ScriptWarning], position: String) {
    print("\n── \(position)  \(automation.id): \(automation.description ?? "(no description)")")
    for warning in warnings {
        print("   ⚠ " + describe(warning, in: automation))
    }
    for file in automation.files {
        print("\n   \(automation.relativePath(of: file))")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            print("   (can't be shown: not text)")
            continue
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let width = String(lines.count).count
        for (number, line) in lines.enumerated() where number < lines.count - 1 || !line.isEmpty {
            print("   " + String(number + 1).padded(to: width) + " │ " + line)
        }
    }
    print()
}

/// `deletes files (line 26: trash "${items[@]}")`, with the file's name when the automation is a folder; a long
/// line is cut, since the review shows it in full.
func describe(_ warning: ScriptWarning, in automation: Automation) -> String {
    let file = automation.files.count > 1 ? "\(automation.relativePath(of: warning.file)) " : ""
    let text = warning.text.count > 60 ? warning.text.prefix(59) + "…" : warning.text
    guard let line = warning.line else { return "\(warning.concern) (\(file)\(text))" }
    return "\(warning.concern) (\(file)line \(line): \(text))"
}

private func approve(_ fingerprints: [String: String], of source: String, store: CollectionStore) throws {
    do {
        try store.approve(fingerprints, in: source)
    } catch {
        printError("pls: \(error)")
        throw ExitCode.failure
    }
}
