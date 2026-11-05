import Foundation
import FoundationModels
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct NLResolverTests {
    @Test func offersOnlyDescribedAutomationsWithTheirExamples() throws {
        let home = try TempHome()
        try home.write("kill-port.sh", """
        # @pls.description: Kill whatever listens on a TCP port
        # @pls.example: free up port 3000
        # @pls.example: something is stuck on 8080
        """)
        try home.write("dark-mode.applescript", "-- @pls.description: Switch dark mode\n")
        try home.write("undescribed.sh", "echo hi\n")

        let candidates = NLResolver.candidates(in: Library.load(home: home.url))

        #expect(NLResolver.routingList(candidates) == """
        - dark-mode: Switch dark mode
        - kill-port: Kill whatever listens on a TCP port (e.g. "free up port 3000", "something is stuck on 8080")
        """)
    }

    @Test func paramListShowsTypesDescriptionsAndDefaults() throws {
        let automation = try makeAutomation(
            "compress", params: "folder: path = ~/Desktop -- Folder with the images", "quality: int(1...100)"
        )
        #expect(NLResolver.paramList(automation) == """
        - folder (path): Folder with the images [default: ~/Desktop]
        - quality (int(1...100))
        """)
    }

    @Test func fillSchemaBuildsForEveryParamType() throws {
        let automation = try makeAutomation(
            "all", params: "a: string", "b: path", "c: bool", "d: int(1...9)", "e: int", "f: number(0...1)",
            "g: number", "h: enum(x|y)"
        )
        _ = try GenerationSchema(root: NLResolver.fillSchema(automation), dependencies: [])
    }

    @Test func generatedValuesBecomeParamStrings() throws {
        let content = try GeneratedContent(json: """
        {"port": 3000, "ratio": 0.5, "mode": "dark", "force": true, "note": null}
        """)
        #expect(NLResolver.values(in: content) == ["port": "3000", "ratio": "0.5", "mode": "dark", "force": "true"])
    }

    @Test func requestValuesThatDontFitAreLeftOut() throws {
        let automation = try makeAutomation(
            "a", params: "quality: int(1...100) = 80", "mode: enum(dark|light)", "note: string?", "port: int"
        )
        let binding = ParamBinder.bind(
            automation, request: "r", values: ["quality": "150", "mode": "dark", "note": "", "gone": "x"]
        )
        #expect(binding.values == [
            "quality": BoundValue("80", .defaultValue),
            "mode": BoundValue("dark", .request)
        ])
        #expect(binding.missing.map(\.name) == ["port"])
    }

    @Test func unavailableModelHasAReason() {
        #expect(NLResolver.unavailableReason(.available) == nil)
        #expect(NLResolver.unavailableReason(.unavailable(.appleIntelligenceNotEnabled))?
            .contains("Apple Intelligence is off") == true)
        #expect(NLResolver.unavailableReason(.unavailable(.deviceNotEligible)) != nil)
        #expect(NLResolver.unavailableReason(.unavailable(.modelNotReady)) != nil)
    }
}

/// Asks the on-device model about the sample library, so it runs only where the model is available.
@Suite(.timeLimit(.minutes(1)), .enabled(if: SystemLanguageModel.default.isAvailable))
struct NLResolverModelTests {
    private let library = Library.load(
        home: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../examples/home")
    )

    @Test func picksAndFills() async throws {
        let binding = try #require(await NLResolver().resolve("free up port 3000", in: library))
        #expect(binding.automation.id == "kill-port")
        #expect(binding.request == "free up port 3000")
        #expect(binding.values == ["port": BoundValue("3000", .request)])
    }

    @Test func fillsEnums() async throws {
        let binding = try #require(await NLResolver().resolve("switch to dark mode", in: library))
        #expect(binding.automation.id == "dark-mode")
        #expect(binding.values["mode"] == BoundValue("dark", .request))
    }

    @Test func answersNoneWhenNothingFits() async throws {
        #expect(try await NLResolver().resolve("order me a pizza", in: library) == nil)
    }
}
