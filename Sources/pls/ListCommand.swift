import ArgumentParser
import Foundation
import PlsCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List your automations.")

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func run() throws {
        let library = Library.loadDefault()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(library.automations.map(AutomationJSON.init))
            print(String(decoding: data, as: UTF8.self))
        } else {
            printTable(library)
        }
        let broken = library.leftOutIDs.count
        if broken > 0 {
            printError(
                "pls: warning: \(broken) automation\(broken == 1 ? " has" : "s have") problems and "
                    + "\(broken == 1 ? "is" : "are") left out; run `pls doctor`"
            )
        }
    }

    private func printTable(_ library: Library) {
        guard !library.automations.isEmpty else {
            print("No automations yet. Add scripts to \(displayPath(library.automationsDirectory)).")
            return
        }
        let rows = library.automations.map { [$0.id, $0.kind.rawValue, $0.description ?? "(no description)"] }
        table(rows).forEach { print($0) }
    }
}

/// The `list --json` shape. Kept in the CLI: it's an output format, not a model.
struct AutomationJSON: Encodable {
    struct ConfirmWhenJSON: Encodable {
        let param: String
        let choices: [String]
    }

    struct ParamJSON: Encodable {
        let name: String
        let type: String
        let required: Bool
        let `default`: String?
        let description: String?
    }

    let id: String
    let name: String
    let description: String?
    let kind: String
    let source: String
    let script: String
    /// Always asks before running.
    let confirm: Bool
    /// Asks only when `param` has one of `choices`.
    let confirmWhen: ConfirmWhenJSON?
    let background: Bool
    let preview: Bool
    let examples: [String]
    let params: [ParamJSON]

    init(_ automation: Automation) {
        self.id = automation.id
        self.name = automation.name
        self.description = automation.description
        self.kind = automation.kind.rawValue
        self.source = automation.sourceURL.path
        self.script = automation.script.path
        switch automation.confirm {
        case .never: (self.confirm, self.confirmWhen) = (false, nil)
        case .always: (self.confirm, self.confirmWhen) = (true, nil)
        case let .when(param, choices): (self.confirm, self.confirmWhen) = (
                false,
                ConfirmWhenJSON(param: param, choices: choices)
            )
        }
        self.background = automation.background
        self.preview = automation.preview
        self.examples = automation.examples
        self.params = automation.params.map { param in
            ParamJSON(
                name: param.name,
                type: param.type.description,
                required: param.requirement == .required,
                default: param.defaultValue,
                description: param.description
            )
        }
    }
}
