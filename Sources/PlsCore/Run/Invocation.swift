import Foundation

/// Exactly what runs for a binding: the program, its arguments and the variables pls sets (SPEC §5).
/// Built without side effects, so `--dry-run` shows the same thing `Runner` would run.
public struct Invocation: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    /// Set on top of the inherited environment.
    public let variables: [String: String]
    /// `PLS_` variables removed from the inherited environment, so a param left empty is really unset even if
    /// the user's shell happens to export the same name.
    public let unset: Set<String>

    public init(_ binding: Binding, homeDirectory: String = NSHomeDirectory()) {
        let automation = binding.automation
        var values: [String] = []
        var variables = ["PLS_ID": automation.id]
        var unset: Set<String> = []

        for param in automation.params {
            let key = Self.variableName(for: param.name)
            guard var value = binding.values[param.name]?.value else {
                values.append("")
                unset.insert(key)
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
        } else {
            unset.insert("PLS_AUTOMATION_DIR")
        }

        let script = automation.script
        switch automation.kind {
        case .applescript:
            self.executable = URL(filePath: "/usr/bin/osascript")
            self.arguments = [script.path] + values
        case .shell:
            if FileManager.default.isExecutableFile(atPath: script.path) {
                self.executable = script
                self.arguments = values
            } else if let interpreter = Self.shebang(of: script), let program = interpreter.first {
                self.executable = URL(filePath: program)
                self.arguments = interpreter.dropFirst() + [script.path] + values
            } else {
                self.executable = URL(filePath: "/bin/zsh")
                self.arguments = [script.path] + values
            }
        }
        self.variables = variables
        self.unset = unset
    }

    /// The environment the program gets.
    public func environment(inheriting base: [String: String]) -> [String: String] {
        base.filter { !unset.contains($0.key) }.merging(variables) { _, new in new }
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

    private static func shellQuoted(_ word: String) -> String {
        if !word.isEmpty, word.wholeMatch(of: /[A-Za-z0-9_\/.:=@%+,-]+/) != nil {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
