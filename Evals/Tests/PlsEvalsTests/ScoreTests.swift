import Foundation
import PlsCore
@testable import PlsEvals
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ScoreTests {
    private let compress = EvalCase(
        request: "compress jpgs in ~/Pictures/trip at 40",
        expect: "compress-images",
        values: ["folder": .oneOf(["~/Pictures/trip"]), "quality": .oneOf(["40"])]
    )

    /// Values the model filled, plus `defaults` left as they were.
    private func verdict(
        _ evalCase: EvalCase, picked: String?, _ filled: [String: String] = [:], defaults: [String: String] = [:]
    ) -> Verdict {
        let values = filled.mapValues { BoundValue($0, .request) }
            .merging(defaults.mapValues { BoundValue($0, .defaultValue) }) { filled, _ in filled }
        return score(evalCase, picked: picked, values: values)
    }

    @Test func rightPickAndValuesPass() {
        #expect(verdict(compress, picked: "compress-images", ["folder": "~/Pictures/trip/", "quality": "40"]).passed)
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
        #expect(verdict(desktop, picked: "compress-images", defaults: ["folder": "~/Desktop"]).passed)
    }

    @Test func valuesTheRequestDidntGiveAreInvented() {
        let squash = EvalCase(request: "my screenshots folder is huge", expect: "compress-images")
        let result = verdict(
            squash, picked: "compress-images", ["folder": "my screenshots folder"], defaults: ["quality": "80"]
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

    @Test(arguments: [("60%", "60"), ("'zsh aliases'", "Zsh Aliases"), ("~/x/", "~/x")])
    func matchingIgnoresCaseQuotesSlashesAndPercent(got: String, want: String) {
        #expect(EvalCase.Expected.oneOf([want]).accepts(got))
    }
}

/// The cases must agree with the eval library, or a typo would look like a model failure (a wrong id or option) or an
/// invented value (a misspelled `allow` name).
@Suite(.timeLimit(.minutes(1)))
struct CasesFileTests {
    private let evals = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../..")

    @Test func casesMatchTheLibrary() throws {
        let cases = try EvalCase.load(evals.appending(path: "cases.yaml"))
        let library = Library.load(home: evals.appending(path: "library"))
        #expect(!cases.isEmpty)

        for evalCase in cases where evalCase.expect != EvalCase.noMatch {
            let automation = try #require(library.automation(id: evalCase.expect), "unknown id in: \(evalCase.request)")
            let params = Dictionary(uniqueKeysWithValues: automation.params.map { ($0.name, $0) })
            for name in evalCase.allow {
                #expect(params[name] != nil, "\(evalCase.request): \(automation.id) has no param \(name)")
            }
            for (name, expected) in evalCase.values {
                let param = try #require(params[name], "\(evalCase.request): \(automation.id) has no param \(name)")
                if case let .oneOf(options) = expected {
                    for option in options {
                        #expect(param.type.problem(with: option) == nil, "\(evalCase.request): \(name)=\(option)")
                    }
                }
            }
        }
    }
}
