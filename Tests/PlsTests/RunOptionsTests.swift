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

    /// A param named after a flag of `pls run` could never be given on the command line: `--version` would print
    /// pls's version. ArgumentParser adds `--version` to every command when the root has one, without listing it.
    @Test func everyFlagOfRunIsAReservedParamName() {
        let help = RunCommand.helpMessage()
        let flags = help.matches(of: /(?m)^ +(?:-[a-z], )?--([a-z-]+)/).map { String($0.1) } + ["version"]
        let names = Set(flags.map { $0.replacing("-", with: "_") })
        #expect(names.subtracting(Param.reservedNames).isEmpty, "\(help)")
    }
}
