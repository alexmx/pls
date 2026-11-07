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
    /// ignores them (the CLI does, so it outlives the script and reports how it ended). An AppleScript's stderr is read
    /// line by line and passed on through `AppleScriptErrors`, so a failing script shows just its message.
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
        let configuration = Configuration(
            executable: .path(FilePath(path)),
            arguments: Arguments(invocation.arguments),
            environment: .exactly(variables),
            platformOptions: options
        )
        let status: TerminationStatus
        do {
            if path == "/usr/bin/osascript" {
                status = try await Subprocess.run(
                    configuration, input: .currentStandardInput, output: .currentStandardOutput, error: .sequence
                ) { execution in
                    for try await line in execution.standardError.strings() {
                        FileHandle.standardError.write(Data((AppleScriptErrors.cleaned(line) + "\n").utf8))
                    }
                }.terminationStatus
            } else {
                status = try await Subprocess.run(
                    configuration,
                    input: .currentStandardInput,
                    output: .currentStandardOutput,
                    error: .currentStandardError
                ).terminationStatus
            }
        } catch let error as SubprocessError where error.code == .executableNotFound {
            throw LaunchError(description: "couldn't start \(path): it, or the program its #! line names, can't be run")
        } catch {
            throw LaunchError(description: "couldn't start \(path): \(error)")
        }
        return status.shellCode
    }

    /// What a preview run of `binding` prints (`Automation.preview`), output and errors together, with its exit status.
    /// It has no input, so it can't stop to ask anything.
    public static func preview(
        _ binding: Binding, environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws(LaunchError) -> (status: Int32, output: String) {
        let invocation = Invocation(binding, preview: true)
        do {
            let result = try await Subprocess.run(
                .path(FilePath(invocation.executable.path)),
                arguments: Arguments(invocation.arguments),
                environment: .exactly(invocation.environment(inheriting: environment)),
                input: .none,
                output: .string(limit: 1 << 16),
                error: .combinedWithOutput
            )
            return (result.terminationStatus.shellCode, result.standardOutput.trimmingCharacters(in: .newlines))
        } catch {
            throw LaunchError(description: "couldn't preview \(invocation.executable.path): \(error)")
        }
    }
}
