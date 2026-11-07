import ArgumentParser
@testable import pls
import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct RunOptionsTests {
    /// PlsCore spells out the run options for dispatch and completion; adding one to `RunOptions` means adding it
    /// there.
    @Test func plsCoreKnowsEverySpelling() {
        let help = RunOptions.helpMessage()
        let spellings = help.matches(of: /(?m)^ +(-[a-z]|--[a-z-]+)(?:, (--[a-z-]+))?/)
            .flatMap { [String($0.1)] + ($0.2.map { [String($0)] } ?? []) }
        #expect(Set(spellings).subtracting(["-h", "--help"]) == Dispatch.runOptions, "\(help)")
    }
}
