import PlsCore

/// The automation and each param's value with where it came from (SPEC §6 "plan display").
func printPlan(_ binding: Binding, write: (String) -> Void = { print($0) }) {
    let automation = binding.automation
    write("→ \(automation.name)  (\(automation.id))")
    let rows = automation.params.map { param -> [String] in
        guard let bound = binding.values[param.name] else {
            return [param.name, param.requirement == .required ? "(missing)" : "(empty)", ""]
        }
        let source = switch bound.source {
        case .defaultValue: "default"
        case .given: "given"
        case .prompted: "entered"
        }
        return [param.name, bound.value.isEmpty ? "\"\"" : bound.value, source]
    }
    let widths = (0..<2).map { column in rows.map { $0[column].count }.max() ?? 0 }
    for row in rows {
        write("    " + [row[0].padded(to: widths[0]), row[1].padded(to: widths[1]), row[2]].joined(separator: "  ")
            .trimmingCharacters(in: .whitespaces))
    }
}

/// The exact command and the PLS_ variables, for --dry-run.
func printInvocation(_ invocation: Invocation) {
    print("\n  command  \(invocation.commandLine)")
    let variables = invocation.variables.sorted { $0.key < $1.key }
        .map { "\($0.key)=\(Invocation.shellQuoted($0.value))" }
    for (index, line) in variables.enumerated() {
        print((index == 0 ? "  env      " : "           ") + line)
    }
}
