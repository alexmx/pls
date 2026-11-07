import Darwin
import Foundation
import Subprocess
import System

/// Automations that run in the background (`@pls.background`), at most one per automation. A job is started detached
/// as the leader of its own process group, with its output in a log, so stopping it ends whatever it started too.
public struct JobStore: Sendable {
    public struct Job: Codable, Sendable, Equatable {
        public let id: String
        public let pid: Int32
        /// When the process started, which tells it apart from a later process that got the same pid.
        public let started: Date
        public let log: URL

        /// Whether its process is still the one pls started.
        public var isRunning: Bool {
            guard let started = JobStore.startTime(of: pid) else { return false }
            return abs(started.timeIntervalSince(self.started)) < 1
        }
    }

    public let directory: URL

    public init(directory: URL = JobStore.defaultDirectory()) {
        self.directory = directory
    }

    /// `jobs/` next to the history: in `$PLS_HOME`, else `$XDG_STATE_HOME/pls`, else `~/.local/state/pls`.
    public static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        Locations.directory(xdgVariable: "XDG_STATE_HOME", fallback: ".local/state", environment: environment)
            .appending(path: "jobs", directoryHint: .isDirectory)
    }

    /// The jobs still running, by id; records of jobs that have ended are removed.
    public func running() -> [Job] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.compactMap { file in
            guard let data = try? Data(contentsOf: file), let job = try? JSONDecoder().decode(Job.self, from: data),
                  job.isRunning else {
                try? FileManager.default.removeItem(at: file)
                return nil
            }
            return job
        }
    }

    /// Ends `id`'s job and everything it started; false if it wasn't running.
    @discardableResult
    public func stop(_ id: String) -> Bool {
        guard let job = running().first(where: { $0.id == id }) else { return false }
        kill(-job.pid, SIGTERM)
        try? FileManager.default.removeItem(at: record(id))
        return true
    }

    /// Starts `invocation` as `id`'s job, replacing a running one, and returns it with the first line it printed:
    /// pls waits up to `wait` for it, or until the job ends.
    public func start(
        _ invocation: Invocation,
        id: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        wait: Duration = .seconds(2)
    ) async throws(Runner.LaunchError) -> (job: Job, output: String) {
        stop(id)
        let log = directory.appending(path: "\(id).log")
        let started: String
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // sh's job control (-m) makes the job the leader of a process group of its own; nohup keeps it running when
            // the terminal closes. sh prints the job's pid and exits, leaving the job to launchd.
            started = try await Subprocess.run(
                .path("/bin/sh"),
                arguments: Arguments(
                    [
                        "-c",
                        #"set -m; log=$1; shift; nohup "$@" </dev/null >"$log" 2>&1 & echo $!"#,
                        "sh",
                        log.path,
                        invocation.executable.path
                    ] + invocation.arguments
                ),
                environment: .custom(Dictionary(uniqueKeysWithValues: invocation.environment(inheriting: environment)
                        .compactMap { key, value in Environment.Key(rawValue: key).map { ($0, value) } })),
                output: .string(limit: 64),
                error: .discarded
            ).standardOutput
        } catch {
            throw Runner.LaunchError(description: "couldn't start \(invocation.executable.path): \(error)")
        }
        guard let pid = Int32(started.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw Runner.LaunchError(description: "couldn't start \(invocation.executable.path) in the background")
        }
        guard let startTime = Self.startTime(of: pid) else {
            // Already finished: there's nothing to keep track of, only what it printed.
            let job = Job(id: id, pid: pid, started: .distantPast, log: log)
            return await (job, Self.firstLine(of: job, within: .zero))
        }
        let job = Job(id: id, pid: pid, started: startTime, log: log)
        do {
            try JSONEncoder().encode(job).write(to: record(id))
        } catch {
            kill(-pid, SIGTERM)
            throw Runner
                .LaunchError(description: "couldn't record the job in \(directory.path): \(error.localizedDescription)")
        }
        return await (job, Self.firstLine(of: job, within: wait))
    }

    private func record(_ id: String) -> URL {
        directory.appending(path: "\(id).json")
    }

    /// The job's first line of output once it's written, or all it wrote if it ended or `wait` ran out first.
    private static func firstLine(of job: Job, within wait: Duration) async -> String {
        let deadline = ContinuousClock.now + wait
        while true {
            let text = (try? String(contentsOf: job.log, encoding: .utf8)) ?? ""
            if let newline = text.firstIndex(of: "\n") {
                return String(text[..<newline])
            }
            if !job.isRunning || ContinuousClock.now >= deadline {
                return text
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// When process `pid` started; nil if there's no such process.
    static func startTime(of pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1e6)
    }
}
