/// The skill `pls skill` prints: a SKILL.md in the Agent Skills format that teaches a coding agent to write
/// automations pls can load, route and fill. The text lives in `skills/use-pls/SKILL.md`, embedded at build time.
public enum AgentSkill {
    public static let markdown = String(decoding: PackageResources.SKILL_md, as: UTF8.self)
}
