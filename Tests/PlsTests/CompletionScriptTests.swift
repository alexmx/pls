@testable import pls
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CompletionScriptTests {
    /// Fails when an ArgumentParser update changes the line the hand-over to `_files` goes after.
    @Test func zshScriptHandsPathsToFileCompletion() throws {
        let script = try #require(CompletionCommand.withFileCompletion(PlsCommand.completionScript(for: .zsh)))
        #expect(script.contains("== ':files' ]]; then _files; return; fi"))
    }

    @Test func aScriptWithoutTheLineIsNil() {
        #expect(CompletionCommand.withFileCompletion("completions=(something else)") == nil)
    }
}
