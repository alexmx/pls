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
            if automation.kind == .shell, Shebang.read(automation.script) == nil {
                warn("has no shebang, so it runs with /bin/zsh", file: automation.script)
            }
        }
        return found
    }
}
