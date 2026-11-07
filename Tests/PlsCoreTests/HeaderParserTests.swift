@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct HeaderParserTests {
    // MARK: header block

    @Test func readsAllKeysFromAShellHeader() throws {
        let result = HeaderParser.parse("""
        #!/bin/zsh
        # @pls.name: Kill process on port
        # @pls.description: Kill whatever is listening on a TCP port
        # @pls.param port: int(1...65535) -- TCP port number
        # @pls.example: free up port 3000
        # @pls.example: something is stuck on 8080
        # @pls.confirm: true
        lsof -ti tcp:$PLS_PORT | xargs kill
        """, commentPrefix: "#")

        #expect(result.diagnostics.isEmpty)
        let metadata = result.metadata
        #expect(metadata.name == "Kill process on port")
        #expect(metadata.description == "Kill whatever is listening on a TCP port")
        #expect(metadata.examples == ["free up port 3000", "something is stuck on 8080"])
        #expect(metadata.confirm == .always)
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
        -- @pls.description: Switch appearance
        -- @pls.param mode: enum(dark|light|toggle) = toggle
        on run argv
        end run
        """, commentPrefix: "--")

        #expect(result.diagnostics.isEmpty)
        #expect(result.metadata.description == "Switch appearance")
        #expect(result.metadata.params.map(\.type) == [.enum(["dark", "light", "toggle"])])
    }

    @Test func stopsAtTheFirstLineOfCode() {
        let result = HeaderParser.parse("""
        # @pls.description: first
        
        # plain comment
        echo hi
        # @pls.description: too late
        """, commentPrefix: "#")

        #expect(result.metadata.description == "first")
        #expect(result.diagnostics.isEmpty)
    }

    @Test func readsAHeaderWithWindowsLineEndings() {
        let result = HeaderParser.parse(
            "#!/bin/zsh\r\n# @pls.description: CRLF\r\n# @pls.param size: huge\r\necho hi\r\n", commentPrefix: "#"
        )
        #expect(result.metadata.description == "CRLF")
        #expect(result.diagnostics.map(\.line) == [3])
        #expect(result.diagnostics.map(\.severity) == [.error])
    }

    @Test func emptyHeaderGivesEmptyMetadata() {
        let result = HeaderParser.parse("#!/bin/sh\necho hi\n", commentPrefix: "#")
        #expect(result.metadata == Metadata())
        #expect(result.diagnostics.isEmpty)
    }

    @Test func unknownKeyIsAWarning() {
        let result = HeaderParser.parse("# @pls.icon: 🔥\n", commentPrefix: "#")
        #expect(result.diagnostics == [Diagnostic(.warning, "unknown key @pls.icon", line: 1)])
    }

    @Test func repeatedDescriptionWarnsAndLastWins() {
        let result = HeaderParser.parse("# @pls.description: a\n# @pls.description: b\n", commentPrefix: "#")
        #expect(result.metadata.description == "b")
        #expect(result.diagnostics.map(\.severity) == [.warning])
        #expect(result.diagnostics.first?.line == 2)
    }

    @Test(arguments: [
        ("# @pls.description:", "@pls.description has no value"),
        ("# @pls.description Missing colon", "expected \"@pls.description: <value>\""),
        ("# @pls.confirm: yes", "@pls.confirm must be true, false or <param>=<choice>,<choice>…"),
        ("# @pls.confirm: action=", "@pls.confirm must be true, false or <param>=<choice>,<choice>…"),
        (
            "# @pls.confirm: mode=dark\n# @pls.param action: enum(shutdown|restart|cancel) = shutdown",
            "confirm names param mode, which the automation doesn't have"
        ),
        (
            "# @pls.confirm: action=halt\n# @pls.param action: enum(shutdown|restart|cancel) = shutdown",
            "confirm: \"halt\" is not one of shutdown, restart, cancel"
        ),
        ("# @pls.param a: int\n# @pls.param a: string", "param \"a\" is declared twice")
    ])
    func keyErrors(header: String, message: String) {
        let errors = HeaderParser.parse(header, commentPrefix: "#").diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.message) == [message])
    }

    /// The confirm line can come before the param it names.
    @Test func confirmForSomeChoices() {
        let result = HeaderParser.parse("""
        # @pls.confirm: action = shutdown, restart
        # @pls.param action: enum(shutdown|restart|cancel) = shutdown
        """, commentPrefix: "#")
        #expect(result.diagnostics.isEmpty)
        #expect(result.metadata.confirm == .when(param: "action", choices: ["shutdown", "restart"]))
    }

    @Test func aConfirmThatDoesntFitIsReportedOnItsLine() {
        let result = HeaderParser.parse(
            "#!/bin/zsh\n# @pls.confirm: action=halt\n# @pls.param action: enum(shutdown|restart|cancel) = shutdown\n",
            commentPrefix: "#"
        )
        #expect(result.diagnostics.map(\.line) == [2])
    }

    @Test func badParamIsReportedWithItsLine() {
        let result = HeaderParser.parse("#!/bin/zsh\n# @pls.param size: huge\n", commentPrefix: "#")
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
        "id: string",
        "home: path",
        "automation_dir: path",
        "port:",
        "port: integer",
        "port: string(5)",
        "port: int(100...1)",
        "port: int(1-100)",
        "ratio: number(a...b)",
        "format: enum()",
        "format: enum(png|png)",
        "format: enum(png||jpg)",
        "port: color(5)",
        "format: enum(png|jpg) = gif",
        "port: int = abc",
        "port: int(1...10) = 11",
        "flag: bool = yes",
        "title: string? = hello",
        "home: path",
        "model: string"
    ])
    func invalidParams(line: String) {
        #expect(throws: ParamError.self) { try HeaderParser.parseParam(line) }
    }

    @Test(arguments: [
        ("port: color(5)", "unknown type \"color\"; use string, path, int, number, bool or enum"),
        ("s: string(5)", "string doesn't take options"),
        ("n: int(1-100)", "int range must look like int(1...100)"),
        ("n: int(a...b)", "int range must be whole numbers with min <= max, like 1...100"),
        ("e: enum", "enum needs distinct, non-empty options"),
        ("t: string? = x", "param t is optional and also has a default; use one")
    ])
    func paramErrorMessages(line: String, message: String) {
        #expect(throws: ParamError(message)) { try HeaderParser.parseParam(line) }
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
