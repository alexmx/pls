import PlsCore

/// The automation and a table of each param's value with where it came from. Values the model read from a request
/// are marked with `●` (and yellow), as they're the ones to check; defaults are dimmed.
func planLines(_ binding: Binding, style: Style) -> [String] {
    let automation = binding.automation
    let title = "→ \(style.bold(automation.name))  \(style.dim("(\(automation.id))"))"
    guard !automation.params.isEmpty else { return [title] }
    let rows = automation.params.map { param -> (cells: [String], source: BoundValue.Source?) in
        guard let bound = binding.values[param.name] else {
            return ([param.name, param.requirement == .required ? "(missing)" : "(empty)", ""], nil)
        }
        let value = bound.value
        let shown = value.isEmpty || Escaping.needsEscaping(value) ? Escaping.quoted(value) : value
        return ([param.name, shown, bound.source.rawValue], bound.source)
    }
    // Styled after the columns are laid out, so escape codes don't count towards their widths.
    let lines = table([["PARAM", "VALUE", "FROM"]] + rows.map(\.cells))
    let header = "    " + style.dim(lines[0])
    let body = zip(rows, lines.dropFirst()).map { row, line in
        switch row.source {
        case .request: "  " + style.yellow("● " + line)
        case .defaultValue: "    " + style.dim(line)
        default: "    " + line
        }
    }
    return [title, "", header] + body
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
