import Foundation

/// Everything `pls doctor` reports: loading problems plus checks on the automations that loaded.
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

    /// Routes each example of `automations` against the whole library and warns about every one the model sends
    /// elsewhere: the examples say what an automation is for, so a miss there means real requests will miss too. Asks
    /// the model once per example, a few seconds each in a big library.
    public static func checkExamples(
        of automations: [Automation], in library: Library, resolver: NLResolver = NLResolver()
    ) async throws(NLResolver.ModelError) -> [Diagnostic] {
        var found: [Diagnostic] = []
        for automation in automations {
            for example in automation.examples {
                let picked = try await resolver.route(example, in: library)
                guard picked?.id != automation.id else { continue }
                found.append(Diagnostic(
                    .warning,
                    "example \"\(example)\" picks \(picked?.id ?? "no automation")",
                    file: automation.declarationURL,
                    automation: automation.id
                ))
            }
        }
        return found
    }
}
