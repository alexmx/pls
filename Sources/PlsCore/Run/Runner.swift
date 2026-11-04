import Foundation

/// Runs an invocation in the current folder with the terminal attached (SPEC §5).
public enum Runner {
    public struct LaunchError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Returns the program's exit status, or 128 + the signal number if a signal ended it (as shells do).
    public static func run(
        _ invocation: Invocation,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws(LaunchError) -> Int32 {
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.environment = invocation.environment(inheriting: environment)

        // Ctrl-C reaches the script too (same process group). Catch it here so pls waits for the script and
        // reports how it ended, instead of quitting under it. A caught signal is reset to its default in the
        // child when it starts, so the script still gets the normal Ctrl-C behavior; SIG_IGN would be inherited.
        let previous = signal(SIGINT) { _ in }
        defer { signal(SIGINT, previous) }

        do {
            try process.run()
        } catch {
            throw LaunchError(
                description: "couldn't start \(invocation.executable.path): \(error.localizedDescription)"
            )
        }
        process.waitUntilExit()
        return process.terminationReason == .uncaughtSignal
            ? 128 + process.terminationStatus
            : process.terminationStatus
    }
}
