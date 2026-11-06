import Foundation

/// Exactly what runs for a binding: the program, its arguments and the variables pls sets (SPEC §5).
/// Built without side effects, so `--dry-run` shows the same thing `Runner` would run.
public struct Invocation: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    /// Set on top of the inherited environment.
    public let variables: [String: String]

    public init(_ binding: Binding, homeDirectory: String = NSHomeDirectory()) {
        let automation = binding.automation
        var values: [String] = []
        var variables = ["PLS_ID": automation.id]

        for param in automation.params {
            let key = Self.variableName(for: param.name)
            guard var value = binding.values[param.name]?.value else {
                values.append("")
                continue
            }
            if param.type == .path {
                value = Self.expandTilde(value, homeDirectory: homeDirectory)
            }
            values.append(value)
            variables[key] = value
        }
        if case let .folder(folder, _) = automation.source {
            variables["PLS_AUTOMATION_DIR"] = folder.path
        }

        let script = automation.script
        switch automation.kind {
        case .applescript:
            self.executable = URL(filePath: "/usr/bin/osascript")
            self.arguments = [script.path] + values
        case .shell:
            // Without a shebang the kernel can't exec the file (ENOEXEC), executable or not; use zsh, as a shell would.
            guard let interpreter = Shebang.read(script), let program = interpreter.first else {
                self.executable = URL(filePath: "/bin/zsh")
                self.arguments = [script.path] + values
                break
            }
            if FileManager.default.isExecutableFile(atPath: script.path) {
                self.executable = script
                self.arguments = values
            } else {
                self.executable = URL(filePath: program)
                self.arguments = interpreter.dropFirst() + [script.path] + values
            }
        }
        self.variables = variables
    }

    /// pls's own settings, which a `pls` run inside a script should see too.
    static let settingVariables: Set<String> = ["PLS_HOME", "PLS_MODEL"]

    /// The environment the program gets: the inherited one minus every `PLS_` variable except the settings, plus
    /// `variables`. So a param left empty is really unset, and a `pls run` inside a script gets nothing from the
    /// automation that called it except how pls is set up (which library, whether to use the model).
    public func environment(inheriting base: [String: String]) -> [String: String] {
        base.filter { !$0.key.hasPrefix("PLS_") || Self.settingVariables.contains($0.key) }
            .merging(variables) { _, new in new }
    }

    /// The command as you'd type it in a shell, for display.
    public var commandLine: String {
        ([executable.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    /// `older_than_days` → `PLS_OLDER_THAN_DAYS`.
    private static func variableName(for param: String) -> String {
        "PLS_" + param.uppercased()
    }

    /// `~` and `~/x` use `homeDirectory`; `~user/x` is left to the system.
    static func expandTilde(_ path: String, homeDirectory: String) -> String {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory + path.dropFirst()
        }
        return path.hasPrefix("~") ? (path as NSString).expandingTildeInPath : path
    }

    /// `word`, quoted for a shell only if it needs to be; control characters use `$'…'` to stay on one line.
    public static func shellQuoted(_ word: String) -> String {
        if !word.isEmpty, word.wholeMatch(of: /[A-Za-z0-9_\/.:=@%+,-]+/) != nil {
            return word
        }
        if Escaping.needsEscaping(word) {
            return "$'" + Escaping.escaped(word, quote: "'") + "'"
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
