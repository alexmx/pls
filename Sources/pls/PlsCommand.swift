import ArgumentParser
import Foundation
import PlsCore

/// Natural-language dispatch happens before ArgumentParser (SPEC §6, §10): a known command or option wins, anything
/// else is a request. A default subcommand can't do this, as its name would become one more word a request can't
/// start with.
///
/// Commands that prompt must run on the main thread: prompting from a background thread, Ctrl-C and SIGTERM didn't end
/// pls. So `main` parses and runs commands itself on the main actor, rather than through ArgumentParser's async `main`,
/// which would run them on a background thread. That covers synchronous commands; an async command's `run()` is
/// `@MainActor` itself (doctor, requests), since an async call would otherwise leave the main actor.
@main
@MainActor
enum Main {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let commands = PlsCommand.configuration.subcommands.compactMap { $0.configuration.commandName }
        if Dispatch.isRequest(arguments, commands: commands) {
            await RequestCommand.main(arguments)
            return
        }
        do {
            var command = try PlsCommand.parseAsRoot(arguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            PlsCommand.exit(withError: error)
        }
    }
}

struct PlsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pls",
        abstract: "Run your own automations: shell scripts and AppleScript, which can also run Shortcuts.",
        usage: """
        pls <subcommand>
        pls "<request>" [--yes] [--dry-run]
        """,
        discussion: """
        Anything that isn't a subcommand is a request in plain words: `pls "free up port 3000"`. Apple's on-device \
        model picks the automation and its values, and pls shows the plan before running it.
        """,
        version: Pls.version,
        subcommands: [
            ListCommand.self,
            ShowCommand.self,
            RunCommand.self,
            AgainCommand.self,
            HistoryCommand.self,
            DoctorCommand.self
        ]
    )
}

/// Exit codes from SPEC §6.
enum Exit {
    static let usage = ExitCode(64)
    static let notFound = ExitCode(65)
    static let modelUnavailable = ExitCode(69)
    static let cannotRun = ExitCode(126)
    static let cancelled = ExitCode(130)
}

extension Library {
    static func loadDefault() -> Library {
        load(home: defaultHome())
    }

    /// The automation with `id`, or a printed explanation and exit 65.
    func require(_ id: String) throws -> Automation {
        guard let automation = automation(id: id) else {
            printError("pls: no automation with id \(id)")
            if leftOutIDs.contains(id) {
                printError("pls: \(id) has problems that keep it from loading; run `pls doctor`")
            }
            throw Exit.notFound
        }
        return automation
    }
}

/// `/Users/me/.config/pls` → `~/.config/pls`.
func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = url.path
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
