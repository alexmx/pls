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

    @Test(arguments: [(100, nil), (3071, nil), (3072, "may fail"), (4096, "may fail"), (4097, "will fail")])
    func budgetWarnsAsTheRoutingListFillsTheContext(tokens: Int, warning: String?) {
        let budget = RoutingBudget(tokens: tokens, contextSize: 4096, automations: 3)
        if let warning {
            #expect(budget.warning?.contains(warning) == true)
        } else {
            #expect(budget.warning == nil)
        }
    }

    /// A big library is shortlisted, and even its fallback reads only the closest few, so its total doesn't matter.
    @Test func aShortlistedLibraryWarnsOnlyForWhatARequestReads() {
        #expect(RoutingBudget(tokens: 17000, contextSize: 4096, automations: 300).warning == nil)
        #expect(RoutingBudget(tokens: 40000, contextSize: 4096, automations: 300).warning?
            .contains("will fail") == true)
    }

    @Test func budgetNeedsTheModel() async {
        await #expect(throws: NLResolver.ModelError.self) {
            try await NLResolver(environment: ["PLS_MODEL": "off"])
                .routingBudget(for: Library.load(home: URL(filePath: "/nonexistent")))
        }
    }

    @Test func plsModelOffTurnsTheModelOff() {
        #expect(NLResolver.unavailableReason(.available, environment: ["PLS_MODEL": "off"])?
            .contains("PLS_MODEL=off") == true)
        #expect(NLResolver.unavailableReason(.available, environment: ["PLS_MODEL": "on"]) == nil)
        #expect(NLResolver.unavailableReason(.available, environment: [:]) == nil)
    }

    @Test func unavailableModelHasAReason() {
        #expect(NLResolver.unavailableReason(.available, environment: [:]) == nil)
        #expect(NLResolver.unavailableReason(.unavailable(.appleIntelligenceNotEnabled), environment: [:])?
            .contains("Apple Intelligence is off") == true)
        #expect(NLResolver.unavailableReason(.unavailable(.deviceNotEligible), environment: [:]) != nil)
        #expect(NLResolver.unavailableReason(.unavailable(.modelNotReady), environment: [:]) != nil)
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

    @Test func countsTheRoutingListAgainstTheContext() async throws {
        let budget = try await NLResolver(environment: [:]).routingBudget(for: library)
        #expect(budget.automations == 4)
        #expect(budget.tokens > 0)
        #expect(budget.tokens < budget.contextSize)
    }

    @Test func answersNoneWhenNothingFits() async throws {
        #expect(try await NLResolver().resolve("order me a pizza", in: library) == nil)
    }

    /// A routing list too big for the model's context gets its own message, not the generic "couldn't answer". It takes
    /// a library small enough not to be shortlisted, with descriptions far longer than any real one.
    @Test func aRoutingListTooBigForTheContextSaysSo() async throws {
        let home = try TempHome()
        let filler = Array(repeating: "and then tidy the files in the folder", count: 40).joined(separator: " ")
        for index in 0..<Shortlist.threshold {
            try home.write("task-\(index).sh", "# @pls.description: Do task number \(index) \(filler)\n")
        }
        let library = Library.load(home: home.url)
        let error = await #expect(throws: NLResolver.ModelError.self) {
            try await NLResolver(environment: [:]).resolve("free up port 3000", in: library)
        }
        #expect(error?.description.contains("don't fit in the model's context") == true, "\(String(describing: error))")
    }

    /// A big library is shortlisted, and even when nothing fits, its fallback reads only the closest few.
    @Test func aBigLibraryStillFitsTheContext() async throws {
        let home = try TempHome()
        for index in 0..<300 {
            try home.write("task-\(index).sh", """
            # @pls.description: Do task number \(index) with the files in a folder and report how it went afterwards
            # @pls.example: run task \(index) on my documents folder please
            """)
        }
        #expect(try await NLResolver(environment: [:])
            .resolve("order me a pizza", in: Library.load(home: home.url)) == nil)
    }

    /// "none" is a valid id, so the no-match answer must be something an id can't be.
    @Test func anAutomationCalledNoneIsntTheNoMatchAnswer() async throws {
        let home = try TempHome()
        try home.write("none.sh", "# @pls.description: Do nothing at all\n")
        try home.write("kill-port.sh", "# @pls.description: Kill whatever listens on a TCP port\n")
        #expect(try await NLResolver().resolve("order me a pizza", in: Library.load(home: home.url)) == nil)
    }
}
