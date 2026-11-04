import ArgumentParser
import Foundation
import PlsCore

@main
struct PlsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pls",
        abstract: "Run your own automations: shell scripts, AppleScript and Shortcuts.",
        version: Pls.version,
        subcommands: [ListCommand.self, ShowCommand.self, DoctorCommand.self]
    )

    /// Every subcommand in SPEC §6, including ones not built yet, so doctor flags clashing ids early.
    static let commandNames: Set<String> = [
        "list", "show", "run", "again", "history", "shortcuts", "doctor", "completion", "help"
    ]
}

/// Exit codes from SPEC §6.
enum Exit {
    static let notFound = ExitCode(65)
}

extension Library {
    static func loadDefault() -> Library {
        load(home: defaultHome())
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
