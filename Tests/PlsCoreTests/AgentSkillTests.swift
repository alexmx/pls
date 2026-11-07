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
        #expect(frontmatter["name"] == "pls")
        let description = try #require(frontmatter["description"])
        #expect(!description.isEmpty && description.count <= 1024)
    }

    @Test func listsTheReservedParamNames() {
        for name in Param.reservedNames {
            #expect(AgentSkill.markdown.contains("`\(name)`"))
        }
    }

    /// Every example is a valid automation: written into a library, each one loads and doctor finds nothing.
    @Test func examplesAreAutomationsWithoutProblems() throws {
        let blocks = Self.codeBlocks()
        try #require(blocks.count == 4)

        let home = try TempHome()
        for (index, block) in blocks.enumerated() {
            switch block.language {
            case "zsh": try home.write("example-\(index).sh", block.code)
            case "applescript": try home.write("example-\(index).applescript", block.code)
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
    }

    /// The example scripts parse: `zsh -n` for shell, `osacompile` for AppleScript.
    @Test func exampleScriptsParse() throws {
        let scripts = Self.codeBlocks().filter { $0.language != "yaml" }
        try #require(!scripts.isEmpty)
        let folder = FileManager.default.temporaryDirectory.appending(path: "pls-skill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for (index, script) in scripts.enumerated() {
            let isAppleScript = script.language == "applescript"
            let file = folder.appending(path: "example-\(index).\(isAppleScript ? "applescript" : "sh")")
            try script.code.write(to: file, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(filePath: isAppleScript ? "/usr/bin/osacompile" : "/bin/zsh")
            process.arguments = isAppleScript ? ["-o", "/dev/null", file.path] : ["-n", file.path]
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "example \(index) (\(script.language)) doesn't parse")
        }
    }

    /// The fenced code blocks, in order.
    private static func codeBlocks() -> [(language: String, code: String)] {
        AgentSkill.markdown.matches(of: /(?ms)^```(\w+)\n(.*?)^```$/).map { (String($0.1), String($0.2)) }
    }
}
