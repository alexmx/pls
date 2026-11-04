import Foundation

/// Everything `pls doctor` reports (SPEC §9): loading problems plus checks on the automations that loaded.
public enum Doctor {
    public static func check(_ library: Library) -> [Diagnostic] {
        var found = library.diagnostics
        for automation in library.automations {
            func warn(_ message: String, file: URL = automation.declarationURL) {
                found.append(Diagnostic(.warning, message, file: file, automation: automation.id))
            }
            if automation.description == nil {
                warn("no description, so natural-language requests will never pick it")
            }
            if automation.kind == .shell,
               !FileManager.default.isExecutableFile(atPath: automation.script.path),
               !hasShebang(automation.script) {
                warn("not executable and has no shebang, so it will run with /bin/zsh", file: automation.script)
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
