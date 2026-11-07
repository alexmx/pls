import Foundation
import NaturalLanguage
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ShortlistTests {
    /// `count` automations: filler ones, with a port killer among them when asked.
    private func automations(_ count: Int, withPortKiller: Bool = true) throws -> [Automation] {
        var automations = try (0..<count).map { index in
            var metadata = Metadata()
            metadata.description = "Rename the photos in album number \(index) by the date they were taken"
            metadata.examples = ["sort album \(index) by date"]
            return Automation(
                id: "album-\(index)",
                kind: .shell,
                source: .file(URL(filePath: "/tmp/\(index).sh")),
                metadata: metadata
            )
        }
        if withPortKiller {
            var metadata = Metadata()
            metadata.description = "Kill whatever process is listening on a TCP port"
            metadata.examples = ["free up port 3000"]
            automations.insert(
                Automation(
                    id: "kill-port",
                    kind: .shell,
                    source: .file(URL(filePath: "/tmp/k.sh")),
                    metadata: metadata
                ),
                at: count / 2
            )
        }
        return automations
    }

    @Test func aLibraryOfThirtyOrFewerIsKeptWhole() throws {
        let library = try automations(29)
        #expect(Shortlist.candidates(for: "free up port 8080", among: library) == library)
    }

    /// The sentence embedding is English only; another language would rank by noise.
    @Test func aRequestInAnotherLanguageKeepsEveryAutomation() throws {
        let library = try automations(40)
        #expect(Shortlist
            .candidates(for: "Bitte gib den Port achttausend frei, er ist blockiert", among: library) == library)
    }

    @Test(arguments: ["show open PRs", "toggle mute", "Xcode froze", "flip bluetooth", "free up port 3000"])
    func aShortEnglishRequestIsntTakenForAnotherLanguage(_ request: String) {
        #expect(!Shortlist.isClearlyNotEnglish(request))
    }

    @Test(arguments: [
        "Bitte gib den Port achttausend frei, er ist blockiert",
        "Mets l'écran en mode sombre, s'il te plaît"
    ])
    func aSentenceInAnotherLanguageIsRecognized(_ request: String) {
        #expect(Shortlist.isClearlyNotEnglish(request))
    }

    @Test(.enabled(if: NLEmbedding.sentenceEmbedding(for: .english) != nil))
    func aBigLibraryIsCutToTheClosestTenInOrder() throws {
        let library = try automations(40)
        let shortlist = Shortlist.candidates(for: "something is stuck on port 8080, kill it", among: library)
        #expect(shortlist.count == Shortlist.size)
        #expect(shortlist.contains { $0.id == "kill-port" })
        let positions = shortlist.compactMap { picked in library.firstIndex { $0.id == picked.id } }
        #expect(positions == positions.sorted())
    }
}
