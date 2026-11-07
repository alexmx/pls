import ArgumentParser
import PlsCore

struct CompletionCommand: ParsableCommand {
    enum Shell: String, CaseIterable, ExpressibleByArgument {
        case zsh

        var completionShell: CompletionShell {
            switch self {
            case .zsh: .zsh
            }
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "completion",
        abstract: "Print the shell completion script.",
        discussion: """
        Tab then completes commands, automation ids, and a run's param names, choices and paths. Add this to ~/.zshrc, \
        after compinit:
        
          source <(pls completion zsh)
        """
    )

    @Argument(help: "The shell to complete in.")
    var shell: Shell

    func run() {
        let script = PlsCommand.completionScript(for: shell.completionShell)
        print(Self.withFileCompletion(script) ?? script)
    }

    /// The words a custom completion prints for `completion`: the suggestions, or a marker the script hands over to
    /// zsh's file completion. Completer escapes colons in its suggestions, so none of them can be the marker.
    static func words(for completion: Completer.Completion) -> [String] {
        switch completion {
        case let .suggestions(suggestions): suggestions
        case .files: [filesMarker]
        }
    }

    private static let filesMarker = ":files"

    /// ArgumentParser's zsh script with a line that hands the marker over to `_files`, zsh's own file completion
    /// (custom completions can only list words). Nil if the line its custom completions are read in has changed.
    static func withFileCompletion(_ script: String) -> String? {
        let readCompletions = #"completions=("${(@f)"$("${command_name}" "${@}" "${command_line[@]}")"}")"#
        guard let range = script.range(of: readCompletions) else { return nil }
        let handOver = #"if [[ "${completions[1]}" == '\#(filesMarker)' ]]; then _files; return; fi"#
        return script.replacingCharacters(in: range, with: "\(readCompletions)\n    \(handOver)")
    }
}
