@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CompleterTests {
    private let home: TempHome
    private let library: Library

    init() throws {
        self.home = try TempHome()
        try home.write("kill-port.sh", "# @pls.description: Kill a port\n")
        try home.write("clean.sh", """
        # @pls.name: Clean
        # @pls.param mode: enum(fast|deep|a:b) = fast -- How hard
        # @pls.param older_than_days: int = 7
        # @pls.param quiet: bool = false -- Say nothing
        """)
        try home.write("broken.sh", "# @pls.param x: nope\n")
        self.library = Library.load(home: home.url)
    }

    /// Completes the last word of `line`; a line ending in a space completes an empty word.
    private func complete(_ line: String) -> [String] {
        let words = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        return Completer.run(words, current: words.count - 1, library: library)
    }

    private let names = [
        "--mode:How hard", "--older-than-days:int", "--quiet:Say nothing", "--no-quiet:Say nothing"
    ]

    @Test func idsAreDescribedAndSkipBrokenAutomations() {
        #expect(Completer.ids(in: library) == ["clean:Clean", "kill-port:Kill a port"])
    }

    @Test(arguments: ["pls run ", "pls run k", "pls run -y ", "pls run --dry-run -y kill"])
    func idsBeforeTheID(line: String) {
        #expect(complete(line) == ["clean:Clean", "kill-port:Kill a port"])
    }

    @Test func nothingForAnUnknownID() {
        #expect(complete("pls run nope --").isEmpty)
    }

    @Test(arguments: ["pls run clean -", "pls run clean --o", "pls run -y clean --yes --"])
    func namesWhenTheWordStartsWithADash(line: String) {
        #expect(complete(line) == names)
    }

    @Test(arguments: [
        "pls run clean --mode deep -",
        "pls run clean --mode=deep -",
        "pls run clean deep -"
    ])
    func namesLeaveOutGivenParams(line: String) {
        #expect(complete(line) == Array(names.dropFirst()))
    }

    @Test(arguments: ["pls run clean --no-quiet -", "pls run clean --quiet -", "pls run clean --quiet=true -"])
    func aBoolGivenEitherWayIsLeftOut(line: String) {
        #expect(complete(line) == Array(names.prefix(2)))
    }

    @Test(arguments: ["pls run clean --mode ", "pls run clean --mode d", "pls run clean ", "pls run clean --quiet "])
    func optionsOfTheParamTheWordFills(line: String) {
        #expect(complete(line) == ["fast", "deep", "a\\:b"])
    }

    @Test func optionsFollowDeclaredOrderAfterNamedParams() {
        #expect(complete("pls run clean --mode deep 3 ") == ["true", "false"])
        #expect(complete("pls run clean --older-than-days 3 deep ") == ["true", "false"])
    }

    @Test(arguments: ["pls run clean deep ", "pls run clean --older-than-days ", "pls run clean deep 3 true "])
    func nothingForParamsWithoutOptions(line: String) {
        #expect(complete(line).isEmpty)
    }

    @Test func afterADoubleDashEverythingIsAValue() {
        #expect(complete("pls run clean -- -") == ["fast", "deep", "a\\:b"])
        #expect(complete("pls run clean -- --mode ").isEmpty)
    }
}
