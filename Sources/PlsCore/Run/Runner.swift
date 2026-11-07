import Darwin
import Foundation
import Subprocess
import System

/// Runs an invocation in the current folder with the terminal attached.
///
/// The script stays in the caller's process group, which is the terminal's foreground group: there Ctrl-C reaches it
/// and it can read from the terminal. (Foundation's `Process` moves it into a group of its own, where neither works;
/// swift-subprocess only does that when asked.)
public enum Runner {
    public struct LaunchError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Returns the program's exit status, or 128 + the signal number if a signal ended it (as shells do).
    ///
    /// SIGINT and SIGQUIT are reset to their defaults in the script, so it can be interrupted even when the caller
    /// ignores them (the CLI does, so it outlives the script and reports how it ended).
    public static func run(
        _ invocation: Invocation,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws(LaunchError) -> Int32 {
        var options = PlatformOptions()
        options.preSpawnProcessConfigurator = { attributes, _ in
            var defaults = sigset_t()
            sigemptyset(&defaults)
            sigaddset(&defaults, SIGINT)
            sigaddset(&defaults, SIGQUIT)
            posix_spawnattr_setsigdefault(&attributes, &defaults)
            var mask = sigset_t()
            sigemptyset(&mask)
            posix_spawnattr_setsigmask(&attributes, &mask)
            var flags: Int16 = 0
            posix_spawnattr_getflags(&attributes, &flags)
            posix_spawnattr_setflags(&attributes, flags | Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        }
        let variables = invocation.environment(inheriting: environment)
        let path = invocation.executable.path
        let status: TerminationStatus
        do {
            status = try await Subprocess.run(
                .path(FilePath(path)),
                arguments: Arguments(invocation.arguments),
                environment: .custom(Dictionary(uniqueKeysWithValues: variables.compactMap { key, value in
                    Environment.Key(rawValue: key).map { ($0, value) }
                })),
                platformOptions: options,
                input: .currentStandardInput,
                output: .currentStandardOutput,
                error: .currentStandardError
            ).terminationStatus
        } catch let error as SubprocessError where error.code == .executableNotFound {
            throw LaunchError(description: "couldn't start \(path): it, or the program its #! line names, can't be run")
        } catch {
            throw LaunchError(description: "couldn't start \(path): \(error)")
        }
        return switch status {
        case let .exited(code): code
        case let .signaled(signal): 128 + signal
        }
    }
}
