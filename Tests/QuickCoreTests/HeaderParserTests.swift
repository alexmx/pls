@testable import QuickCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct HeaderParserTests {
    // MARK: header block

    @Test func readsAllKeysFromAShellHeader() throws {
        let result = HeaderParser.parse("""
        #!/bin/zsh
        # @quick.name: Kill process on port
        # @quick.description: Kill whatever is listening on a TCP port
        # @quick.param port: int(1...65535) -- TCP port number
        # @quick.example: free up port 3000
        # @quick.example: something is stuck on 8080
        # @quick.confirm: true
        lsof -ti tcp:$QUICK_PORT | xargs kill
        """, commentPrefix: "#")

        #expect(result.diagnostics.isEmpty)
        let metadata = result.metadata
        #expect(metadata.name == "Kill process on port")
        #expect(metadata.description == "Kill whatever is listening on a TCP port")
        #expect(metadata.examples == ["free up port 3000", "something is stuck on 8080"])
        #expect(metadata.confirm)
        let port = try Param(
            name: "port",
            type: .int(1...65535),
            requirement: .required,
            description: "TCP port number"
        )
        #expect(metadata.params == [port])
    }

    @Test func readsAnAppleScriptHeader() {
        let result = HeaderParser.parse("""
        -- @quick.description: Switch appearance
        -- @quick.param mode: enum(dark|light|toggle) = toggle
        on run argv
        end run
        """, commentPrefix: "--")

        #expect(result.diagnostics.isEmpty)
        #expect(result.metadata.description == "Switch appearance")
        #expect(result.metadata.params.map(\.type) == [.enum(["dark", "light", "toggle"])])
    }

    @Test func stopsAtTheFirstLineOfCode() {
        let result = HeaderParser.parse("""
        # @quick.description: first
        
        # plain comment
        echo hi
        # @quick.description: too late
        """, commentPrefix: "#")

        #expect(result.metadata.description == "first")
        #expect(result.diagnostics.isEmpty)
    }

    @Test func emptyHeaderGivesEmptyMetadata() {
        let result = HeaderParser.parse("#!/bin/sh\necho hi\n", commentPrefix: "#")
        #expect(result.metadata == Metadata())
        #expect(result.diagnostics.isEmpty)
    }

    @Test func unknownKeyIsAWarning() {
        let result = HeaderParser.parse("# @quick.icon: 🔥\n", commentPrefix: "#")
        #expect(result.diagnostics == [Diagnostic(.warning, "unknown key @quick.icon", line: 1)])
    }

    @Test func repeatedDescriptionWarnsAndLastWins() {
        let result = HeaderParser.parse("# @quick.description: a\n# @quick.description: b\n", commentPrefix: "#")
        #expect(result.metadata.description == "b")
        #expect(result.diagnostics.map(\.severity) == [.warning])
        #expect(result.diagnostics.first?.line == 2)
    }

    @Test(arguments: [
        ("# @quick.description:", "@quick.description has no value"),
        ("# @quick.description Missing colon", "expected \"@quick.description: <value>\""),
        ("# @quick.confirm: yes", "@quick.confirm must be true or false"),
        ("# @quick.param a: int\n# @quick.param a: string", "param \"a\" is declared twice")
    ])
    func keyErrors(header: String, message: String) {
        let errors = HeaderParser.parse(header, commentPrefix: "#").diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.message) == [message])
    }

    @Test func badParamIsReportedWithItsLine() {
        let result = HeaderParser.parse("#!/bin/zsh\n# @quick.param size: huge\n", commentPrefix: "#")
        #expect(result.metadata.params.isEmpty)
        #expect(result.diagnostics.map(\.line) == [2])
        #expect(result.diagnostics.map(\.severity) == [.error])
    }

    // MARK: param lines

    @Test(arguments: [
        ("folder: path", "folder", ParamType.path, Param.Requirement.required, nil as String?),
        ("title: string?", "title", .string, .optional, nil),
        ("verbose: bool = false", "verbose", .bool, .defaultValue("false"), nil),
        ("count: int = 3 -- How many", "count", .int(nil), .defaultValue("3"), "How many"),
        ("quality: int(1...100) = 80", "quality", .int(1...100), .defaultValue("80"), nil),
        ("ratio: number(0...1) = 0.5", "ratio", .number(0...1), .defaultValue("0.5"), nil),
        ("format: enum( png | jpg ) = jpg", "format", .enum(["png", "jpg"]), .defaultValue("jpg"), nil),
        ("body: string = \"\"", "body", .string, .defaultValue(""), nil),
        ("msg: string = 'two words' -- Commit message", "msg", .string, .defaultValue("two words"), "Commit message"),
        ("folder: path = ~/My Stuff -- Where", "folder", .path, .defaultValue("~/My Stuff"), "Where"),
        ("flag: string = a--b", "flag", .string, .defaultValue("a--b"), nil)
    ])
    func validParams(
        line: String, name: String, type: ParamType, requirement: Param.Requirement, description: String?
    ) throws {
        let param = try HeaderParser.parseParam(line)
        #expect(try param == Param(name: name, type: type, requirement: requirement, description: description))
    }

    @Test(arguments: [
        "no colon here",
        "Port: int",
        "help: bool",
        "port:",
        "port: integer",
        "port: string(5)",
        "port: int(100...1)",
        "port: int(1-100)",
        "ratio: number(a...b)",
        "format: enum()",
        "format: enum(png|png)",
        "format: enum(png|jpg) = gif",
        "port: int = abc",
        "port: int(1...10) = 11",
        "flag: bool = yes",
        "title: string? = hello"
    ])
    func invalidParams(line: String) {
        #expect(throws: ParamError.self) { try HeaderParser.parseParam(line) }
    }

    // MARK: model

    @Test(arguments: ["string", "path", "bool", "int", "int(1...100)", "number", "number(0...1.5)", "enum(png|jpg)"])
    func typeDescriptionRoundTrips(spec: String) throws {
        #expect(try HeaderParser.parseType(spec).description == spec)
    }

    @Test func defaultNameComesFromTheID() {
        let automation = Automation(
            id: "kill-port", kind: .shell, source: .file(.init(filePath: "/x")), metadata: Metadata()
        )
        #expect(automation.name == "Kill port")
    }
}
