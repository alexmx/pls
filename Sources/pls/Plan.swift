import PlsCore

/// The automation and each param's value with where it came from.
func planLines(_ binding: Binding) -> [String] {
    let automation = binding.automation
    let rows = automation.params.map { param -> [String] in
        guard let bound = binding.values[param.name] else {
            return [param.name, param.requirement == .required ? "(missing)" : "(empty)", ""]
        }
        let value = bound.value
        let shown = value.isEmpty || Escaping.needsEscaping(value) ? Escaping.quoted(value) : value
        return [param.name, shown, bound.source.rawValue]
    }
    return ["→ \(automation.name)  (\(automation.id))"] + table(rows, indent: "    ")
}

/// The exact command and the PLS_ variables, for --dry-run.
func invocationLines(_ invocation: Invocation) -> [String] {
    let variables = invocation.variables.sorted { $0.key < $1.key }
        .map { "\($0.key)=\(Invocation.shellQuoted($0.value))" }
    return ["", "  command  \(invocation.commandLine)"]
        + variables.enumerated().map { index, line in (index == 0 ? "  env      " : "           ") + line }
}

/// A preview run's output under a heading, and its exit status when it failed.
func previewLines(status: Int32, output: String) -> [String] {
    let lines = output.isEmpty ? ["(it printed nothing)"] : output.split(
        separator: "\n",
        omittingEmptySubsequences: false
    )
    .map(String.init)
    return ["", "  preview"] + lines
        .map { "    " + $0 } + (status == 0 ? [] : ["    (the preview failed with exit \(status))"])
}
