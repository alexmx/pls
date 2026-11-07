@testable import pls
import Testing

@Suite(.timeLimit(.minutes(1)))
struct PromptTests {
    @Test(arguments: ["", "plain", "  spaced  ", "café"])
    func aOneLineValueIsPrefilled(_ value: String) {
        #expect(Prompt.canPrefill(value))
    }

    /// A prefilled line separator would break the line being edited, as a newline would.
    @Test(arguments: ["a\nb", "a\tb", "a\u{2028}b", "a\u{2029}b"])
    func aValueThatBreaksTheLineIsNot(_ value: String) {
        #expect(!Prompt.canPrefill(value))
    }
}
