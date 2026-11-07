import Foundation
import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SkillCommandTests {
    /// The built `pls skill` prints the skill and nothing else, so `pls skill > SKILL.md` is a valid skill file.
    @Test func printsTheSkill() throws {
        let process = Process()
        process.executableURL = ExitCodeTests.binary()
        process.arguments = ["skill"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(String(decoding: output, as: UTF8.self) == AgentSkill.markdown + "\n")
    }
}
