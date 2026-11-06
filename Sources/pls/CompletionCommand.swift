import ArgumentParser

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
        Tab then completes commands, automation ids, and a run's param names and choices. Add this to ~/.zshrc, \
        after compinit:
        
          source <(pls completion zsh)
        """
    )

    @Argument(help: "The shell to complete in.")
    var shell: Shell

    func run() {
        print(PlsCommand.completionScript(for: shell.completionShell))
    }
}
