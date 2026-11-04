import ArgumentParser
import Foundation
import PlsCore

@main
struct PlsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pls",
        abstract: "Run your own automations: shell scripts, AppleScript and Shortcuts.",
        version: Pls.version,
        subcommands: [ListCommand.self, ShowCommand.self, RunCommand.self, DoctorCommand.self]
    )
}

/// Exit codes from SPEC §6.
enum Exit {
    static let usage = ExitCode(64)
    static let notFound = ExitCode(65)
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
            printError("No automation with id \(id).")
            if leftOutIDs.contains(id) {
                printError("\(id) has problems that keep it from loading; run `pls doctor`.")
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
