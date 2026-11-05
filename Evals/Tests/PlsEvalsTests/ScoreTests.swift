import Foundation
@testable import PlsEvals
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ScoreTests {
    private let compress = EvalCase(
        request: "compress jpgs in ~/Pictures/trip at 40",
        expect: "compress-images",
        values: ["folder": .oneOf(["~/Pictures/trip"]), "quality": .oneOf(["40"])]
    )

    private func verdict(
        _ evalCase: EvalCase, picked: String?, _ values: [String: String] = [:], fromRequest: Set<String>? = nil
    ) -> Verdict {
        score(evalCase, picked: picked, values: values, fromRequest: fromRequest ?? Set(values.keys))
    }

    @Test func rightPickAndValuesPass() {
        #expect(verdict(compress, picked: "compress-images", ["folder": "~/Pictures/trip/", "quality": "40.0"]).passed)
    }

    @Test func wrongPickFailsWithoutCheckingValues() {
        let result = verdict(compress, picked: "resize-images", ["percent": "40"])
        #expect(result == Verdict(routed: false, wrongValues: [], invented: []))
    }

    @Test func missingOrWrongValuesFail() {
        let result = verdict(compress, picked: "compress-images", ["quality": "60"])
        #expect(result.wrongValues == ["folder=∅ (want ~/Pictures/trip)", "quality=60 (want 40)"])
        #expect(!result.passed)
    }

    @Test func aDefaultCanSatisfyAnExpectedValue() {
        let desktop = EvalCase(request: "r", expect: "compress-images", values: ["folder": .oneOf(["~/Desktop"])])
        #expect(verdict(desktop, picked: "compress-images", ["folder": "~/Desktop"], fromRequest: []).passed)
    }

    @Test func valuesTheRequestDidntGiveAreInvented() {
        let squash = EvalCase(request: "my screenshots folder is huge", expect: "compress-images")
        let result = verdict(
            squash,
            picked: "compress-images",
            ["folder": "my screenshots folder", "quality": "80"],
            fromRequest: ["folder"]
        )
        #expect(result.invented == ["folder=my screenshots folder"])
        #expect(!result.passed)
    }

    @Test func allowedAndAnyValuesArentInvented() {
        let note = EvalCase(request: "r", expect: "new-note", values: ["title": .any], allow: ["body"])
        #expect(verdict(note, picked: "new-note", ["title": "Dentist", "body": "call on monday"]).passed)
        #expect(!verdict(note, picked: "new-note", ["body": "call on monday"]).passed)
    }

    @Test func noneCases() {
        let weather = EvalCase(request: "what's the weather", expect: "none")
        #expect(verdict(weather, picked: nil).passed)
        #expect(!verdict(weather, picked: "dark-mode").passed)
        #expect(!verdict(compress, picked: nil).passed)
    }

    @Test(arguments: [("60%", "60"), ("'zsh aliases'", "Zsh Aliases"), ("~/x/", "~/x"), ("7.0", "7")])
    func matchingIgnoresCaseQuotesSlashesAndNumberForm(got: String, want: String) {
        #expect(EvalCase.Expected.oneOf([want]).accepts(got))
    }

    @Test func theCasesFileLoads() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../cases.yaml")
        let cases = try EvalCase.load(file)
        #expect(cases.count == 30)
        #expect(cases.filter { $0.expect == EvalCase.noMatch }.count == 3)
        let quit = try #require(cases.first { $0.expect == "quit-apps" })
        #expect(quit.values["except"] == .oneOf(["Slack, Safari", "Slack,Safari", "Slack and Safari"]))
        #expect(cases.first { $0.expect == "new-note" }?.values["title"] == .any)
        #expect(cases.first { $0.request == "mute" }?.values["level"] == .oneOf(["0"]))
    }
}
