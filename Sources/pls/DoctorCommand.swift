import ArgumentParser
import Foundation
import PlsCore

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Check your automations for problems, and whether the model can be used."
    )

    func run() async throws {
        let library = Library.loadDefault()
        let errors = report(Doctor.check(library), in: library)
        await reportModel(for: library)
        if errors > 0 {
            throw ExitCode(1)
        }
    }

    /// Prints the problems grouped by file and returns how many are errors.
    private func report(_ problems: [Diagnostic], in library: Library) -> Int {
        print("Library: \(displayPath(library.automationsDirectory))")
        guard !problems.isEmpty else {
            let count = library.automations.count
            print("No problems found in \(count) automation\(count == 1 ? "" : "s").")
            return 0
        }

        // Group by file, keeping the order problems were found in.
        var files: [URL?] = []
        for problem in problems where !files.contains(problem.file) {
            files.append(problem.file)
        }
        for file in files {
            print("\n" + (file.map { relativePath($0, to: library.automationsDirectory) } ?? "(library)"))
            for problem in problems where problem.file == file {
                let location = problem.line.map { "line \($0): " } ?? ""
                print("  \(problem.severity.rawValue.padded(to: 7))  \(location)\(problem.message)")
            }
        }

        let errors = problems.count { $0.severity == .error }
        let warnings = problems.count - errors
        print("\n\(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s")")
        return errors
    }

    /// Whether requests can use the model and how much of its context routing takes (SPEC §9). Info only: it never
    /// changes the exit code.
    private func reportModel(for library: Library) async {
        do throws(NLResolver.ModelError) {
            let budget = try await NLResolver().routingBudget(for: library)
            guard budget.automations > 0 else {
                print("\nModel: available · no automation has a description, so requests have nothing to pick from")
                return
            }
            let percent = budget.tokens * 100 / budget.contextSize
            let count = budget.automations
            print("\nModel: available · routing uses \(budget.tokens) of \(budget.contextSize) tokens (\(percent)%) "
                + "for \(count) automation\(count == 1 ? "" : "s")")
            if let warning = budget.warning {
                print("  warning  \(warning)")
            }
        } catch {
            switch error {
            case let .unavailable(reason): print("\nModel: \(reason); requests use word matching")
            case let .failed(reason): print("\nModel: available, but \(reason)")
            }
        }
    }
}

/// The file's path inside the library folder, or its full display path if it's elsewhere.
private func relativePath(_ file: URL, to directory: URL) -> String {
    // Resolve both: listings return /private/tmp/… while $PLS_HOME may say /tmp/….
    let base = directory.resolvingSymlinksInPath().path + "/"
    let path = file.resolvingSymlinksInPath().path
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : displayPath(file)
}
