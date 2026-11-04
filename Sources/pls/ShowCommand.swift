import ArgumentParser
import PlsCore

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show one automation in detail.")

    @Argument(help: "The automation's id.")
    var id: String

    func run() throws {
        let automation = try Library.loadDefault().require(id)

        print("\(automation.name)  (\(automation.id))")
        if let description = automation.description {
            print(description)
        }
        print()
        print("  kind     \(automation.kind.rawValue)")
        print("  source   \(displayPath(automation.sourceURL))")
        if case .folder = automation.source {
            print("  script   \(automation.script.lastPathComponent)")
        }
        print("  confirm  \(automation.confirm ? "always asks before running" : "no")")

        if !automation.params.isEmpty {
            print("\nParams")
            let rows = automation.params.map { param in
                let requirement = switch param.requirement {
                case .required: "required"
                case .optional: "optional"
                case let .defaultValue(value): "default \(value.isEmpty ? "\"\"" : value)"
                }
                return [param.name, param.type.description, requirement, param.description ?? ""]
            }
            let widths = (0..<3).map { column in rows.map { $0[column].count }.max() ?? 0 }
            for row in rows {
                let line = (0..<3).map { row[$0].padded(to: widths[$0]) }.joined(separator: "  ") + "  " + row[3]
                print("  " + line.trimmingCharacters(in: .whitespaces))
            }
        }

        if !automation.examples.isEmpty {
            print("\nExamples")
            for example in automation.examples {
                print("  \"\(example)\"")
            }
        }
    }
}
