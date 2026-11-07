import Foundation

extension Runner {
    /// How a recorded run ended.
    public struct Outcome: Sendable {
        /// The script's exit status (128 + the signal number if a signal ended it).
        public let status: Int32
        /// Set when the run couldn't be written to history; the run itself still happened.
        public let historyError: HistoryStore.WriteError?
    }

    /// Runs `binding` and records the run in `history`. A script that can't be started is not recorded.
    public static func run(
        _ binding: Binding,
        via trigger: HistoryEntry.Trigger,
        history: HistoryStore = HistoryStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws(LaunchError) -> Outcome {
        let started = Date()
        // Duration from a monotonic clock, so a clock change during the run can't make it negative or huge.
        let clock = ContinuousClock.now
        let status = try await run(Invocation(binding), environment: environment)
        let elapsed = ContinuousClock.now - clock
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        do {
            try history.append(HistoryEntry(binding, via: trigger, exit: status, seconds: seconds, at: started))
            return Outcome(status: status, historyError: nil)
        } catch {
            return Outcome(status: status, historyError: error)
        }
    }

    /// How starting a background automation went.
    public struct Started: Sendable {
        public let job: JobStore.Job
        /// The first line the job printed (see `JobStore.start`).
        public let output: String
        public let historyError: HistoryStore.WriteError?
    }

    /// Starts `binding` as a background job, replacing its running one, and records the start in `history`: its
    /// exit status isn't known yet, so it's recorded as 0.
    public static func start(
        _ binding: Binding,
        via trigger: HistoryEntry.Trigger,
        history: HistoryStore = HistoryStore(),
        jobs: JobStore = JobStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws(LaunchError) -> Started {
        let started = Date()
        let (job, output) = try await jobs.start(
            Invocation(binding),
            id: binding.automation.id,
            environment: environment
        )
        do {
            try history.append(HistoryEntry(binding, via: trigger, exit: 0, seconds: 0, at: started))
            return Started(job: job, output: output, historyError: nil)
        } catch {
            return Started(job: job, output: output, historyError: error)
        }
    }
}
