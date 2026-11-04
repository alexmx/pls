import ArgumentParser
import Foundation
import PlsCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Check your automations for problems."
    )

    func run() throws {
        let library = Library.loadDefault()
        let problems = Doctor.check(library)
        print("Library: \(displayPath(library.automationsDirectory))")

        guard !problems.isEmpty else {
            let count = library.automations.count
            print("No problems found in \(count) automation\(count == 1 ? "" : "s").")
            return
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
        if errors > 0 {
            throw ExitCode(1)
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
