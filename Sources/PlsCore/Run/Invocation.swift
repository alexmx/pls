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
            guard let interpreter = Self.shebang(of: script), let program = interpreter.first else {
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

    /// The environment the program gets: the inherited one minus every `PLS_` variable except `PLS_HOME`, plus
    /// `variables`. So a param left empty is really unset, and a `pls run` inside a script gets nothing from the
    /// automation that called it except which library to use.
    public func environment(inheriting base: [String: String]) -> [String: String] {
        base.filter { !$0.key.hasPrefix("PLS_") || $0.key == "PLS_HOME" }.merging(variables) { _, new in new }
    }

    /// The command as you'd type it in a shell, for display.
    public var commandLine: String {
        ([executable.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    /// `older_than_days` → `PLS_OLDER_THAN_DAYS`.
    public static func variableName(for param: String) -> String {
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

    /// The `#!` line split into program and arguments, e.g. `["/usr/bin/env", "python3"]`.
    private static func shebang(of script: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: script) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512),
              let firstLine = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first,
              firstLine.hasPrefix("#!")
        else { return nil }
        let words = firstLine.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
        return words.isEmpty ? nil : words
    }

    /// `word`, quoted for a shell only if it needs to be.
    public static func shellQuoted(_ word: String) -> String {
        if !word.isEmpty, word.wholeMatch(of: /[A-Za-z0-9_\/.:=@%+,-]+/) != nil {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
