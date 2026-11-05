import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ParamBinderTests {
    let compress: Automation

    init() throws {
        self.compress = try makeAutomation(
            "compress",
            params: "folder: path = ~/Desktop", "quality: int(1...100) = 80", "format: enum(jpg|heic) = jpg"
        )
    }

    private func bind(_ automation: Automation, _ arguments: String...) throws -> [String: BoundValue] {
        try ParamBinder.bind(automation, arguments: arguments).values
    }

    @Test func defaultsWhenNothingIsGiven() throws {
        #expect(try bind(compress) == [
            "folder": BoundValue("~/Desktop", .defaultValue),
            "quality": BoundValue("80", .defaultValue),
            "format": BoundValue("jpg", .defaultValue)
        ])
    }

    @Test func positionalValuesFillParamsInOrder() throws {
        #expect(try bind(compress, "~/Pictures", "40") == [
            "folder": BoundValue("~/Pictures", .given),
            "quality": BoundValue("40", .given),
            "format": BoundValue("jpg", .defaultValue)
        ])
    }

    @Test(arguments: [
        ["--quality", "40"],
        ["--quality=40"]
    ])
    func namedValues(arguments: [String]) throws {
        #expect(try ParamBinder.bind(compress, arguments: arguments).values["quality"] == BoundValue("40", .given))
    }

    @Test func positionalValuesSkipParamsGivenByName() throws {
        let values = try bind(compress, "--folder", "/x", "55", "heic")
        #expect(values["folder"] == BoundValue("/x", .given))
        #expect(values["quality"] == BoundValue("55", .given))
        #expect(values["format"] == BoundValue("heic", .given))
    }

    @Test func dashesStandForUnderscores() throws {
        let clean = try makeAutomation(params: "older_than_days: int = 30")
        #expect(try bind(clean, "--older-than-days", "7")["older_than_days"] == BoundValue("7", .given))
        #expect(try bind(clean, "--older_than_days", "7")["older_than_days"] == BoundValue("7", .given))
    }

    @Test func boolFlags() throws {
        let verbose = try makeAutomation(params: "verbose: bool = false", "name: string?")
        #expect(try bind(verbose, "--verbose")["verbose"] == BoundValue("true", .given))
        #expect(try bind(verbose, "--no-verbose")["verbose"] == BoundValue("false", .given))
        #expect(try bind(verbose, "--verbose=false")["verbose"] == BoundValue("false", .given))
        // A bare bool flag doesn't swallow the next word, which stays positional.
        #expect(try bind(verbose, "--verbose", "alex")["name"] == BoundValue("alex", .given))
    }

    @Test func doubleDashMakesTheRestPositional() throws {
        let echo = try makeAutomation(params: "text: string")
        #expect(try bind(echo, "--", "--not-a-flag")["text"] == BoundValue("--not-a-flag", .given))
    }

    @Test func singleDashValuesArePositional() throws {
        let offset = try makeAutomation(params: "by: int")
        #expect(try bind(offset, "-5")["by"] == BoundValue("-5", .given))
    }

    @Test func requiredAndOptionalWithoutValues() throws {
        let port = try makeAutomation(params: "port: int", "host: string?")
        let binding = try ParamBinder.bind(port, arguments: [])
        #expect(binding.values.isEmpty)
        #expect(binding.missing.map(\.name) == ["port"])
    }

    @Test func supplyFillsMissingAfterValidating() throws {
        let port = try makeAutomation(params: "port: int(1...65535)")
        var binding = try ParamBinder.bind(port, arguments: [])
        let param = port.params[0]
        #expect(throws: BindingError("port: 99999 is outside 1...65535")) {
            try binding.supply("99999", for: param, source: .prompted)
        }
        try binding.supply("3000", for: param, source: .prompted)
        #expect(binding.values["port"] == BoundValue("3000", .prompted))
        #expect(binding.missing.isEmpty)
    }

    @Test(arguments: [
        (["99999"], "port: 99999 is outside 1...65535"),
        (["abc"], "port: \"abc\" is not a whole number"),
        (["1", "2"], "too many values: kill-port takes 1 param"),
        (["--port", "1", "2"], "too many values: kill-port takes 1 param and 1 was given by name"),
        (["--host", "x"], "kill-port has no param --host; it takes --port"),
        (["--port"], "--port needs a value"),
        (["--port", "1", "--port", "2"], "port is given twice"),
        (["--no-port"], "kill-port has no param --no-port; it takes --port")
    ])
    func errors(arguments: [String], message: String) throws {
        let killPort = try makeAutomation("kill-port", params: "port: int(1...65535)")
        #expect(throws: BindingError(message)) { try ParamBinder.bind(killPort, arguments: arguments) }
    }

    @Test func errorsForAutomationsWithoutParams() throws {
        let trash = try makeAutomation("empty-trash")
        #expect(throws: BindingError("empty-trash takes no params, but 1 value was given")) {
            try ParamBinder.bind(trash, arguments: ["now"])
        }
        #expect(throws: BindingError("empty-trash has no param --force; it takes none")) {
            try ParamBinder.bind(trash, arguments: ["--force"])
        }
    }

    @Test func invalidEnumAndBoolValues() throws {
        #expect(throws: BindingError("format: \"png\" is not one of jpg, heic")) {
            try ParamBinder.bind(compress, arguments: ["--format", "png"])
        }
        let verbose = try makeAutomation(params: "verbose: bool = false")
        #expect(throws: BindingError("--no-verbose doesn't take a value")) {
            try ParamBinder.bind(verbose, arguments: ["--no-verbose=true"])
        }
    }

    /// The model often fills a param with its default; that's still the default, not a value the request chose.
    @Test func requestValuesEqualToTheDefaultStayDefaults() throws {
        let automation = try makeAutomation("a", params: "editor: enum(xcode|cursor) = xcode", "project: string")
        let binding = ParamBinder.bind(automation, request: "r", values: ["editor": "xcode", "project": "site"])
        #expect(binding.values == [
            "editor": BoundValue("xcode", .defaultValue),
            "project": BoundValue("site", .request)
        ])
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

    // MARK: editing in review

    private func reviewed() throws -> Binding {
        let automation = try makeAutomation(
            "a", params: "port: int(1...65535)", "quality: int = 80", "note: string?"
        )
        return ParamBinder.bind(automation, request: "r", values: ["port": "3000", "quality": "60", "note": "hi"])
    }

    @Test func editingChangesTheValueAndMarksIt() throws {
        var binding = try reviewed()
        try binding.edit("3001", for: binding.automation.params[0])
        #expect(binding.values["port"] == BoundValue("3001", .edited))
        #expect(binding.isEdited)
    }

    @Test func keepingTheValueIsNoEdit() throws {
        var binding = try reviewed()
        for param in binding.automation.params {
            try binding.edit(binding.values[param.name]?.value ?? "", for: param)
        }
        #expect(try binding == reviewed())
        #expect(!binding.isEdited)
    }

    @Test func resettingAValueThatIsAlreadyTheDefaultIsNoEdit() throws {
        let automation = try makeAutomation("a", params: "quality: int = 80", "note: string?")
        var binding = ParamBinder.bind(automation, request: "r", values: [:])
        try binding.edit("", for: automation.params[0])
        try binding.edit("", for: automation.params[1])
        #expect(binding == ParamBinder.bind(automation, request: "r", values: [:]))
        #expect(!binding.isEdited)
    }

    @Test func emptyResetsADefaultAndClearsAnOptional() throws {
        var binding = try reviewed()
        try binding.edit("", for: binding.automation.params[1])
        try binding.edit("", for: binding.automation.params[2])
        #expect(binding.values["quality"] == BoundValue("80", .defaultValue))
        #expect(binding.values["note"] == nil)
        #expect(binding.isEdited)
    }

    @Test func editsMustFit() throws {
        var binding = try reviewed()
        let port = binding.automation.params[0]
        #expect(throws: BindingError("port: required")) { try binding.edit("", for: port) }
        #expect(throws: BindingError("port: 0 is outside 1...65535")) { try binding.edit("0", for: port) }
        #expect(try binding == reviewed())
    }
}
