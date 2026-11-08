import Foundation

/// Lines in an automation worth reading before turning it on: what can do lasting harm, or hides what it does. These
/// help a person review a script; they are hints, not a safety check, and nothing turns on or off because of them.
public struct ScriptWarning: Sendable, Equatable {
    public let concern: String
    public let file: URL
    /// nil when it's about the whole file (one that can't be read).
    public let line: Int?
    public let text: String
}

public enum ScriptWarnings {
    private struct Rule {
        let concern: String
        let patterns: [Regex<Substring>]
    }

    private static let deletes = "deletes files"

    /// A rule is about one line; comments and lines that only print are skipped first. Built on each use: regexes
    /// aren't Sendable, and this is cheap next to reading the files.
    private static var rules: [Rule] {
        [
            Rule(concern: deletes, patterns: [
                /(?:^|[\s;&|(`])rm\s/, /(?:^|[\s;&|(`])trash\s/, /\s-delete\b/, /diskutil\s+erase/, /(?i)empty trash/,
                /(?i)\bdelete\s+(?:file|folder|every|item|disk)/
            ]),
            Rule(concern: "needs admin rights", patterns: [/\bsudo\b/, /(?i)with administrator privileges/]),
            Rule(concern: "runs code it downloads", patterns: [
                /\b(?:curl|wget)\b[^\n]*\|\s*(?:sudo\s+)?(?:ba|z)?sh\b/,
                /\b(?:curl|wget)\b[^\n]*\|\s*(?:python|perl|ruby)/,
                /(?:^|[\s;&|(])eval\s/, /source\s+<\(\s*(?:curl|wget)/, /\$\(\s*(?:curl|wget)\b/
            ]),
            Rule(concern: "sends data out", patterns: [
                /\bcurl\b[^\n]*\s(?:-d|--data\S*|-F|--form|-T|--upload-file)\b/, /\bwget\b[^\n]*--post/,
                /(?:^|[\s;&|(])nc\s/,
                /(?:^|[\s;&|(])scp\s/
            ]),
            Rule(concern: "reads secrets", patterns: [
                /security\s+(?:find|dump|export)/, /\.ssh\//, /Library\/Keychains/, /\.aws\//,
                /Library\/(?:Application Support\/(?:Google\/Chrome|Firefox)|Safari)/
            ]),
            Rule(concern: "starts itself later", patterns: [
                /launchctl\s+(?:load|bootstrap|submit|enable)/, /\bcrontab\b/, /Launch(?:Agents|Daemons)/
            ]),
            Rule(concern: "hides what it does", patterns: [
                // Decoding is only hiding when what's decoded is run, or is written into the script itself.
                /(?:base64\s+(?:-d|-D|--decode)|xxd\s+-r)[^\n]*\|\s*(?:sudo\s+)?(?:(?:ba|z)?sh|python|perl|ruby|osascript)\b/,
                /(?:echo|printf|<<<)[^\n]*\|\s*(?:base64\s+(?:-d|-D|--decode)|xxd\s+-r)/,
                /(?:\\x[0-9a-fA-F]{2}){4,}/, /[A-Za-z0-9+\/]{200,}/
            ])
        ]
    }

    /// The warnings for every file `automation` runs: its file, or each in its folder.
    public static func of(_ automation: Automation) -> [ScriptWarning] {
        automation.files.flatMap(warnings(in:))
    }

    private static func warnings(in file: URL) -> [ScriptWarning] {
        func unreadable(_ why: String) -> [ScriptWarning] {
            [ScriptWarning(concern: "can't be read", file: file, line: nil, text: why)]
        }
        // A collection's automation links only within its own folder, where the target is read in its own right.
        if Fingerprint.isSymlink(file) {
            return []
        }
        if file.pathExtension == "scpt" {
            return unreadable("compiled AppleScript, which only Script Editor can show")
        }
        guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8) else {
            return unreadable("not text: a program or other binary")
        }
        // Temporary files the script made itself (`name=$(mktemp …)`) may be removed freely.
        let temporary = Set(text.matches(of: /(\w+)=\$\(mktemp\b/).map { String($0.1) })
        var found: [ScriptWarning] = []
        var concerns: Set<String> = []
        let rules = rules
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.hasPrefix("--") || isOnlyPrinting(line) {
                continue
            }
            for rule in rules where !concerns.contains(rule.concern) {
                guard rule.patterns.contains(where: { line.firstMatch(of: $0) != nil }) else { continue }
                if rule.concern == deletes, removesOnlyTemporaryFiles(line, temporary) {
                    continue
                }
                concerns.insert(rule.concern)
                found.append(ScriptWarning(concern: rule.concern, file: file, line: index + 1, text: line))
            }
        }
        return found
    }

    /// `echo "Restarting…"`: a message, unless it's piped on to something.
    private static func isOnlyPrinting(_ line: String) -> Bool {
        line.firstMatch(of: /^(?:echo|print|printf)\b/) != nil && !line.contains("|")
    }

    /// `rm -f "$input"` where every path removed starts with a variable holding a `mktemp` file.
    private static func removesOnlyTemporaryFiles(_ line: String, _ temporary: Set<String>) -> Bool {
        guard !temporary.isEmpty, let rm = line.firstMatch(of: /\brm\s+(.*)/) else { return false }
        let targets = rm.1.split(separator: " ").filter { !$0.hasPrefix("-") }.map { String($0) }
        return !targets.isEmpty && targets.allSatisfy { target in
            guard let name = target.firstMatch(of: /^["']?\$\{?(\w+)/)?.1 else { return false }
            return temporary.contains(String(name))
        }
    }
}
