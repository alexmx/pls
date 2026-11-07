import Darwin
import Foundation

/// Runs an invocation in the current folder with the terminal attached.
///
/// Uses `posix_spawn` rather than `Process`: `Process` puts the child in a new process group, which isn't the
/// terminal's foreground group, so Ctrl-C never reaches the script and reading from the terminal stops it (SIGTTIN).
/// Here the script stays in the caller's group.
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
    ) throws(LaunchError) -> Int32 {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGINT)
        sigaddset(&defaults, SIGQUIT)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        let path = invocation.executable.path
        let argv = [path] + invocation.arguments
        let envp = invocation.environment(inheriting: environment).map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let spawned = withCStrings(argv) { argv in
            withCStrings(envp) { envp in
                posix_spawn(&pid, path, nil, &attributes, argv, envp)
            }
        }
        guard spawned == 0 else {
            throw LaunchError(description: "couldn't start \(path): \(String(cString: strerror(spawned)))")
        }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else {
                throw LaunchError(description: "lost track of \(path): \(String(cString: strerror(errno)))")
            }
        }
        // The <sys/wait.h> macros aren't available in Swift: low 7 bits = terminating signal, next byte = exit code.
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
    }

    /// A NULL-terminated C array of `strings`, valid inside `body`.
    private static func withCStrings<R>(
        _ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R
    ) -> R {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return body(pointers)
    }
}
