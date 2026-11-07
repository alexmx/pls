import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SkillCommandTests {
    /// The built `pls skill` prints the skill and nothing else, so `pls skill > SKILL.md` is a valid skill file.
    @Test func printsTheSkill() async throws {
        let result = try await BuiltPls().run("skill")
        #expect(result.status == 0)
        #expect(result.stdout == AgentSkill.markdown)
    }
}
