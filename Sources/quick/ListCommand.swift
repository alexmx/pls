import ArgumentParser
import Foundation
import QuickCore

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
        let broken = Set(library.diagnostics.filter { $0.severity == .error }.compactMap(\.file)).count
        if broken > 0 {
            printError(
                "\(broken) automation\(broken == 1 ? " has" : "s have") problems and \(broken == 1 ? "is" : "are") "
                    + "left out; run `quick doctor`."
            )
        }
    }

    private func printTable(_ library: Library) {
        guard !library.automations.isEmpty else {
            print("No automations yet. Add scripts to \(displayPath(library.automationsDirectory)).")
            return
        }
        let idWidth = library.automations.map(\.id.count).max() ?? 0
        let kindWidth = library.automations.map(\.kind.rawValue.count).max() ?? 0
        for automation in library.automations {
            print([
                automation.id.padded(to: idWidth),
                automation.kind.rawValue.padded(to: kindWidth),
                automation.description ?? "(no description)"
            ].joined(separator: "  "))
        }
    }
}

/// The `list --json` shape. Kept in the CLI: it's an output format, not a model.
struct AutomationJSON: Encodable {
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
    let confirm: Bool
    let examples: [String]
    let params: [ParamJSON]

    init(_ automation: Automation) {
        self.id = automation.id
        self.name = automation.name
        self.description = automation.description
        self.kind = automation.kind.rawValue
        self.source = automation.sourceURL.path
        self.script = automation.script.path
        self.confirm = automation.confirm
        self.examples = automation.examples
        self.params = automation.params.map { param in
            let defaultValue: String? = if case let .defaultValue(value) = param.requirement {
                value
            } else {
                nil
            }
            return ParamJSON(
                name: param.name,
                type: param.type.description,
                required: param.requirement == .required,
                default: defaultValue,
                description: param.description
            )
        }
    }
}
