import Foundation

/// Everything `pls doctor` reports (SPEC §9): loading problems plus checks on the automations that loaded.
public enum Doctor {
    /// - Parameter commandNames: CLI subcommands; an automation with one of these ids can't be run as `pls <id>`.
    public static func check(_ library: Library, commandNames: Set<String>) -> [Diagnostic] {
        var found = library.diagnostics
        for automation in library.automations {
            let file = automation.sourceURL
            if commandNames.contains(automation.id) {
                found.append(Diagnostic(
                    .warning,
                    "id \(automation.id) is also a command; run it with `pls run \(automation.id)`",
                    file: file
                ))
            }
            if automation.description == nil {
                found.append(Diagnostic(
                    .warning, "no description, so natural-language requests will never pick it", file: file
                ))
            }
            if automation.kind == .shell,
               !FileManager.default.isExecutableFile(atPath: automation.script.path),
               !hasShebang(automation.script) {
                found.append(Diagnostic(
                    .warning, "not executable and has no shebang, so it will run with /bin/zsh",
                    file: automation.script
                ))
            }
        }
        return found
    }

    private static func hasShebang(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data("#!".utf8)
    }
}
