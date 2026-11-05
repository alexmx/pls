import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct FuzzyMatcherTests {
    private let library = Library.load(
        home: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../examples/home")
    )

    private func closest(_ request: String) -> [String] {
        FuzzyMatcher.closest(to: request, in: library.automations).map(\.id)
    }

    @Test func wordsAreLowercasedWithoutFillerOrPunctuation() {
        #expect(FuzzyMatcher.words("Free up THE port 3000, please! It's stuck") == [
            "free",
            "up",
            "port",
            "3000",
            "stuck"
        ])
    }

    @Test func ranksTheAutomationSharingTheMostWordsFirst() {
        #expect(closest("kill the process on port 3000").first == "kill-port")
        #expect(closest("compress my pictures").first == "compress-images")
    }

    @Test func aSharedBeginningCountsToo() {
        #expect(closest("make it darker").first == "dark-mode")
        #expect(closest("compressing").first == "compress-images")
    }

    @Test func nothingInCommonIsNoMatch() {
        #expect(closest("order me a pizza").isEmpty)
        #expect(closest("").isEmpty)
    }

    @Test func returnsAtMostTheLimitInAStableOrder() throws {
        let home = try TempHome()
        for id in ["d", "c", "b", "a"] {
            try home.write("\(id).sh", "# @pls.description: Clean things\n")
        }
        let automations = Library.load(home: home.url).automations
        #expect(FuzzyMatcher.closest(to: "clean", in: automations).map(\.id) == ["a", "b", "c"])
        #expect(FuzzyMatcher.closest(to: "clean", in: automations, limit: 1).map(\.id) == ["a"])
    }
}
