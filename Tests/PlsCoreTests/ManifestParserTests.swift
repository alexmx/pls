@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ManifestParserTests {
    @Test func readsAFullManifest() throws {
        let result = ManifestParser.parse("""
        name: Compress images
        description: Re-encode images in a folder at lower quality
        entry: run.sh
        kind: applescript
        confirm: true
        examples:
          - shrink my screenshots
        params:
          - name: folder
            type: path
            default: ~/Desktop
            description: Folder containing the images
          - name: quality
            type: int
            min: 1
            max: 100
            default: 80
          - name: ratio
            type: number
            min: 0
            max: 1.5
          - name: format
            type: enum
            options: [png, jpg, heic]
            default: png
          - name: verbose
            type: bool
            default: false
          - name: title
            type: string
            optional: true
        """)

        #expect(result.diagnostics.isEmpty)
        #expect(result.entry == "run.sh")
        #expect(result.kind == .applescript)
        let metadata = result.metadata
        #expect(metadata.name == "Compress images")
        #expect(metadata.description == "Re-encode images in a folder at lower quality")
        #expect(metadata.confirm == .always)
        #expect(metadata.examples == ["shrink my screenshots"])
        #expect(try metadata.params == [
            Param(
                name: "folder",
                type: .path,
                requirement: .defaultValue("~/Desktop"),
                description: "Folder containing the images"
            ),
            Param(name: "quality", type: .int(1...100), requirement: .defaultValue("80"), description: nil),
            Param(name: "ratio", type: .number(0...1.5), requirement: .required, description: nil),
            Param(
                name: "format",
                type: .enum(["png", "jpg", "heic"]),
                requirement: .defaultValue("png"),
                description: nil
            ),
            Param(name: "verbose", type: .bool, requirement: .defaultValue("false"), description: nil),
            Param(name: "title", type: .string, requirement: .optional, description: nil)
        ])
    }

    @Test func minimalManifestNeedsOnlyEntry() {
        let result = ManifestParser.parse("entry: run.sh\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.metadata == Metadata())
        #expect(result.kind == nil)
    }

    @Test func unknownKeysAreWarningsWithLines() {
        let result = ManifestParser.parse("""
        entry: run.sh
        icon: fire
        params:
          - name: a
            type: string
            colour: red
        """)
        #expect(result.diagnostics == [
            Diagnostic(.warning, "unknown key icon", line: 2),
            Diagnostic(.warning, "unknown param key colour", line: 6)
        ])
        #expect(result.metadata.params.count == 1)
    }

    @Test(arguments: [
        ("confirm: {action: [shutdown, restart]}", ["shutdown", "restart"]),
        ("confirm:\n  action: shutdown", ["shutdown"])
    ])
    func confirmForSomeChoices(confirm: String, choices: [String]) {
        let result = ManifestParser.parse("""
        entry: run.sh
        \(confirm)
        params:
          - {name: action, type: enum, options: [shutdown, restart, cancel], default: shutdown}
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.metadata.confirm == .when(param: "action", choices: choices))
    }

    @Test(arguments: [
        ("name: x\n", "missing entry (the script file to run)"),
        ("entry: run.sh\nkind: python\n", "kind must be shell or applescript"),
        ("entry: run.sh\nbackground: yes\n", "background must be true or false"),
        (
            "entry: run.sh\nconfirm: maybe\n",
            "confirm must be true, false or a mapping like {action: [shutdown, restart]}"
        ),
        (
            "entry: run.sh\nconfirm: yes\n",
            "confirm must be true, false or a mapping like {action: [shutdown, restart]}"
        ),
        ("entry: run.sh\nconfirm: {mode: dark}\n", "confirm names param mode, which the automation doesn't have"),
        ("entry: run.sh\nparams:\n  - {name: a, type: int, optional: yes}\n", "optional must be true or false"),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: string, default: [x, y]}\n",
            "default for a must be a single value; use \"\" for empty text"
        ),
        (
            "entry: run.sh\nparams:\n  - name: a\n    type: string\n    default:\n",
            "default for a must be a single value; use \"\" for empty text"
        ),
        ("entry: run.sh\ndescription: [a, b]\n", "description must be non-empty text"),
        ("entry: run.sh\nexamples: hello\n", "examples must be a list"),
        ("entry: run.sh\nparams: {a: 1}\n", "params must be a list"),
        ("entry: run.sh\nparams: [hello]\n", "each param must be a mapping with name and type"),
        ("entry: run.sh\nparams:\n  - type: int\n", "param is missing name"),
        ("entry: run.sh\nparams:\n  - name: a\n", "param a is missing type"),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: int}\n  - {name: a, type: int}\n",
            "param \"a\" is declared twice"
        ),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: color}\n",
            "unknown type \"color\"; use string, path, int, number, bool or enum"
        ),
        ("entry: run.sh\nparams:\n  - {name: a, type: int, min: 1}\n", "give both min and max, or neither"),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: int, min: 1.5, max: 3}\n",
            "int range must be whole numbers with min <= max, like 1...100"
        ),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: int, min: 5, max: 1}\n",
            "int range must be whole numbers with min <= max, like 1...100"
        ),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: string, options: [x]}\n",
            "string doesn't take options"
        ),
        ("entry: run.sh\nparams:\n  - {name: a, type: enum}\n", "enum needs distinct, non-empty options"),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: enum, options: [x, x]}\n",
            "enum needs distinct, non-empty options"
        ),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: enum, options: [x], default: y}\n",
            "default for a: \"y\" is not one of x"
        ),
        (
            "entry: run.sh\nparams:\n  - {name: a, type: int, default: 1, optional: true}\n",
            "param a is optional and also has a default; use one"
        ),
        ("entry: run.sh\nparams:\n  - {name: a, type: int, optional: sometimes}\n", "optional must be true or false"),
        (
            "entry: run.sh\nparams:\n  - {name: Bad, type: int}\n",
            "param name \"Bad\" must be lowercase letters, digits and _, starting with a letter"
        ),
        ("- just\n- a list\n", "manifest must be a YAML mapping of keys like name, description, entry")
    ])
    func errors(yaml: String, message: String) {
        let errors = ManifestParser.parse(yaml).diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.message) == [message])
    }

    @Test func quotedEmptyDefaultIsEmptyText() {
        let result = ManifestParser.parse("entry: run.sh\nparams:\n  - {name: body, type: string, default: \"\"}\n")
        #expect(result.diagnostics.isEmpty)
        #expect(result.metadata.params.map(\.requirement) == [.defaultValue("")])
    }

    @Test func invalidYAMLIsAnError() {
        let result = ManifestParser.parse("entry: [unclosed\n")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.message.hasPrefix("invalid YAML") == true)
    }

    @Test func errorPointsAtTheParamLine() {
        let result = ManifestParser.parse("entry: run.sh\nparams:\n  - name: a\n    type: color\n")
        #expect(result.diagnostics.map(\.line) == [3])
    }
}
