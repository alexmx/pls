import Foundation
@testable import PlsCore
import Testing
import Yams

@Suite(.timeLimit(.minutes(1)))
struct AgentSkillTests {
    /// Agent Skills loaders need the frontmatter first, with a name and a description of at most 1024 characters.
    @Test func startsWithValidFrontmatter() throws {
        let parts = AgentSkill.markdown.components(separatedBy: "---\n")
        try #require(parts.count >= 3 && parts[0].isEmpty, "no frontmatter at the top")
        let frontmatter = try #require(try Yams.load(yaml: parts[1]) as? [String: String])
        #expect(frontmatter["name"] == "use-pls")
        let description = try #require(frontmatter["description"])
        #expect(!description.isEmpty && description.count <= 1024)
    }

    /// The skill is a plain file, so nothing else keeps its list in step with the parsers'.
    @Test func listsTheReservedParamNames() {
        let list = Param.reservedNames.sorted().map { "`\($0)`" }.joined(separator: ", ")
        #expect(AgentSkill.markdown.contains("reserved:\n\(list)."))
    }

    /// Every example is a valid automation: written into a library, each one loads, doctor finds nothing, and its
    /// script parses.
    @Test func examplesAreValidAutomations() throws {
        let blocks = Self.codeBlocks()
        try #require(blocks.count == 4)

        let home = try TempHome()
        var scripts: [URL] = []
        for (index, block) in blocks.enumerated() {
            switch block.language {
            case "zsh": try scripts.append(home.write("example-\(index).sh", block.code))
            case "applescript": try scripts.append(home.write("example-\(index).applescript", block.code))
            case "yaml":
                // A manifest's first line names its folder, `# compress-images/manifest.yaml`; its entry gets a stub.
                let folder = try #require(block.code.firstMatch(of: /^# (\S+)\/manifest\.yaml\n/)?.1)
                let manifest = try #require(try Yams.load(yaml: block.code) as? [String: Any])
                let entry = try #require(manifest["entry"] as? String)
                try home.write("\(folder)/manifest.yaml", block.code)
                try home.write("\(folder)/\(entry)", "#!/bin/zsh\n")
            default: Issue.record("unexpected code block language \(block.language)")
            }
        }
        let library = Library.load(home: home.url)
        #expect(library.automations.count == blocks.count)
        #expect(Doctor.check(library) == [])
        for script in scripts {
            #expect(try Self.parses(script), "\(script.lastPathComponent) doesn't parse")
        }
    }

    /// Whether `file` parses: `zsh -n` for shell, `osacompile` for AppleScript.
    private static func parses(_ file: URL) throws -> Bool {
        let isAppleScript = file.pathExtension == "applescript"
        let process = Process()
        process.executableURL = URL(filePath: isAppleScript ? "/usr/bin/osacompile" : "/bin/zsh")
        process.arguments = isAppleScript ? ["-o", "/dev/null", file.path] : ["-n", file.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The fenced code blocks, in order.
    private static func codeBlocks() -> [(language: String, code: String)] {
        AgentSkill.markdown.matches(of: /(?ms)^```(\w+)\n(.*?)^```$/).map { (String($0.1), String($0.2)) }
    }
}
