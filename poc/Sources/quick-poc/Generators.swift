import Foundation
import FoundationModels

// MARK: - One-off shell commands

@Generable
struct ShellPlan {
    @Guide(description: "A single zsh command or short pipeline that runs on macOS")
    var command: String
    @Guide(description: "One short sentence explaining what the command does")
    var explanation: String
    @Guide(description: "true if the command deletes, overwrites or moves files, or needs sudo")
    var destructive: Bool
}

func generateOneOff(_ task: String, model: ModelChoice) async throws -> ShellPlan {
    let session = model.session(instructions: """
        You write zsh commands for macOS. macOS uses BSD tools, not GNU: \
        e.g. `sed -i ''`, `stat -f`, `du -d 1`, no `--sort` flags on BSD tools.
        Prefer tools that ship with macOS: find, xargs, sort, du, sips, mdfind, osascript, \
        pbcopy, open, shortcuts, curl, lsof, ps, top -l 1.
        Do not use sudo unless the task requires it. Output exactly one command.
        """)
    return try await session.respond(to: task, generating: ShellPlan.self, options: deterministic).content
}

// MARK: - New automations

@Generable
struct DraftParam {
    @Guide(description: "snake_case parameter name")
    var name: String
    @Guide(.anyOf(["string", "path", "int", "bool"]))
    var type: String
    var description: String
    @Guide(description: "Default value as text, or empty if the parameter is required")
    var defaultValue: String
}

@Generable
struct DraftAutomation {
    @Guide(description: "short kebab-case id, e.g. zip-folder")
    var id: String
    var name: String
    @Guide(description: "One sentence describing what it does")
    var description: String
    @Guide(.anyOf(["shell", "applescript"]))
    var kind: String
    @Guide(description: "Inputs the script needs from the user. Empty if none.")
    var params: [DraftParam]
    @Guide(description: """
        The complete script. For shell: a zsh script that reads each parameter from an \
        environment variable named QUICK_<NAME IN UPPERCASE>. For applescript: use \
        `on run argv` and read parameters from argv in the order declared.
        """)
    var script: String
}

func generateAutomation(_ request: String, model: ModelChoice) async throws -> DraftAutomation {
    let session = model.session(instructions: """
        You create small, reusable macOS automations from a description. \
        Prefer zsh for file and system tasks and AppleScript for controlling apps. \
        Use tools that ship with macOS. Keep scripts short and safe; never use sudo.
        """)
    return try await session.respond(to: request, generating: DraftAutomation.self, options: deterministic).content
}

// MARK: - Static checks

struct CheckResult {
    var syntaxOK: Bool
    var syntaxError: String
    var missingTools: [String]
    var ok: Bool { syntaxOK && missingTools.isEmpty }
}

/// Syntax check with `zsh -n` / `osacompile`, and look for commands that don't exist on this Mac.
func check(script: String, kind: String) -> CheckResult {
    let dir = FileManager.default.temporaryDirectory.appending(path: "quick-poc-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appending(path: kind == "applescript" ? "s.applescript" : "s.zsh")
    try? script.write(to: file, atomically: true, encoding: .utf8)

    if kind == "applescript" {
        let (code, out) = run(["/usr/bin/osacompile", "-o", dir.appending(path: "s.scpt").path, file.path])
        return CheckResult(syntaxOK: code == 0, syntaxError: out, missingTools: [])
    }
    let (code, out) = run(["/bin/zsh", "-n", file.path])
    return CheckResult(syntaxOK: code == 0, syntaxError: out, missingTools: missingTools(in: script))
}

/// Rough: first word after start / | / && / || / ; / $( — good enough to catch invented tools.
private func missingTools(in script: String) -> [String] {
    let skip: Set<String> = ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until",
                             "case", "esac", "function", "local", "export", "return", "sudo", "time", "!", "{", "}",
                             "[", "[[", "]]", "echo", "print", "printf", "cd", "read", "set", "shift", "eval", "exit",
                             "test", "true", "false", "source", ".", "trap", "unset", "typeset", "declare", "setopt"]
    let pattern = /(?:^|\||&&|\|\||;|\$\(|\bthen\b|\bdo\b|\belse\b)\s*([A-Za-z0-9_.\-\/]+)/
    var tools = Set<String>()
    for line in script.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
        for m in line.matches(of: pattern) {
            let word = String(m.1)
            if skip.contains(word) || word.contains("=") || word.hasPrefix("$") || word.hasPrefix("-") { continue }
            if Int(word) != nil { continue }
            tools.insert(word)
        }
    }
    return tools.sorted().filter { run(["/bin/zsh", "-c", "command -v -- \"$0\"", $0]).0 != 0 }
}

@discardableResult
func run(_ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
}
