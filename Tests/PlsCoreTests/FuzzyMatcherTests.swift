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

    @Test(arguments: [
        ("dark", "dark", 1.0),
        ("dark", "darker", 0.5),
        ("compressing", "compress", 0.5),
        ("images", "imagery", 0.5),
        ("app", "appearance", 0.0),
        ("port", "post", 0.0),
        ("do", "dock", 0.0)
    ])
    func similarity(of word: String, and other: String, is expected: Double) {
        #expect(FuzzyMatcher.similarity(word, other) == expected)
        #expect(FuzzyMatcher.similarity(other, word) == expected)
    }

    @Test func aSharedBeginningOfAShortWordIsNoMatch() {
        #expect(closest("what is the weather").isEmpty)
        #expect(closest("how do I install an app").isEmpty)
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
