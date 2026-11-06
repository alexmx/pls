@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct DispatchTests {
    private let commands = ["list", "show", "run", "again", "history", "doctor"]

    @Test(arguments: [
        ["free up port 3000"],
        ["free", "up", "port", "3000"],
        ["run the backup"],
        ["-y", "free up port 3000"],
        ["--yes", "x"],
        ["--dry-run", "x"],
        ["listen", "to", "music"]
    ])
    func isARequest(arguments: [String]) {
        #expect(Dispatch.isRequest(arguments, commands: commands))
    }

    @Test(arguments: [
        [],
        ["list"],
        ["run", "the", "backup"],
        ["help"],
        ["help", "run"],
        ["--help"],
        ["-h"],
        ["--version"],
        ["--bogus", "x"],
        // How the completion script asks for suggestions.
        ["---completion", "run", "--", "positional@0", "2", "0", "pls", "run", ""]
    ])
    func isASubcommand(arguments: [String]) {
        #expect(!Dispatch.isRequest(arguments, commands: commands))
    }
}
