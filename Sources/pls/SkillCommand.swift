import ArgumentParser
import PlsCore

struct SkillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Print a skill that teaches coding agents to write automations for pls.",
        discussion: """
        The skill is a SKILL.md in the Agent Skills format. Save it where your agent looks for skills, for Claude Code:
        
          mkdir -p ~/.claude/skills/pls && pls skill > ~/.claude/skills/pls/SKILL.md
        
        Run it again after updating pls, so the skill matches.
        """
    )

    func run() {
        print(AgentSkill.markdown)
    }
}
