import ArgumentParser
import Foundation
import PlsCore

/// Natural-language dispatch happens before ArgumentParser: a known command or option wins, anything
/// else is a request. A default subcommand can't do this, as its name would become one more word a request can't
/// start with.
///
/// Commands that prompt must run on the main thread: prompting from a background thread, Ctrl-C and SIGTERM didn't end
/// pls. So `main` parses and runs commands itself on the main actor, requests included, rather than through
/// ArgumentParser's async `main`, which would run them on a background thread. That covers synchronous commands; an
/// async command's `run()` is `@MainActor` itself (doctor, requests), since an async call would otherwise leave the
/// main actor.
@main
@MainActor
enum Main {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let commands = PlsCommand.configuration.subcommands.compactMap { $0.configuration.commandName }
        let root: ParsableCommand.Type = Dispatch.isRequest(arguments, commands: commands)
            ? RequestCommand.self : PlsCommand.self
        do {
            var command = try root.parseAsRoot(arguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error, parsedBy: root)
        }
    }

    /// ArgumentParser's errors written like pls's own, `pls: missing expected argument '<id>'` rather than
    /// `Error: Missing…`, with the usage after them. Help, `--version` and thrown exit codes pass through unchanged.
    private static func exit(withError error: Error, parsedBy root: ParsableCommand.Type) -> Never {
        let message = root.fullMessage(for: error)
        let code = root.exitCode(for: error)
        guard code != .success, message.hasPrefix("Error: ") else { root.exit(withError: error) }
        var text = message.dropFirst("Error: ".count)
        // Lowercase a capitalised word (`Missing`), not a name or an option (`--limit`).
        if text.first?.isUppercase == true, text.dropFirst().first?.isLowercase == true {
            text = text.prefix(1).lowercased() + text.dropFirst()
        }
        printError("pls: " + text.trimmingCharacters(in: .newlines))
        Foundation.exit(code.rawValue)
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
            DoctorCommand.self,
            CompletionCommand.self
        ]
    )
}

/// pls's exit codes. Besides these: the script's own code when it ran (128 + the signal if one ended it), and 1 when
/// the model couldn't answer a request (a refusal, an unsupported language, a library too big for its context).
enum Exit {
    /// Usage or validation error, or a question with no terminal to ask in.
    static let usage = ExitCode(64)
    /// Unknown id, or no automation matches a request.
    static let notFound = ExitCode(65)
    /// The model is unavailable and no automation was picked by words instead.
    static let modelUnavailable = ExitCode(69)
    /// The script couldn't be started, e.g. its shebang's interpreter doesn't exist.
    static let cannotRun = ExitCode(126)
    /// Cancelled at a prompt.
    static let cancelled = ExitCode(130)
}

extension Library {
    static func loadDefault() -> Library {
        load(home: defaultHome())
    }

    /// The automation with `id`, or a printed explanation and exit 65.
    func require(_ id: String) throws -> Automation {
        guard let automation = automation(id: id) else {
            printError(leftOutIDs.contains(id)
                ? "pls: \(id) has problems that keep it from loading; run `pls doctor`"
                : "pls: no automation with id \(id); run `pls list` to see them")
            throw Exit.notFound
        }
        return automation
    }
}

/// A value among others on one line: quoted when it's empty or has spaces, newlines or tabs.
func displayValue(_ value: String) -> String {
    value.isEmpty || value.contains(where: \.isWhitespace) || Escaping.needsEscaping(value)
        ? Escaping.quoted(value) : value
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
