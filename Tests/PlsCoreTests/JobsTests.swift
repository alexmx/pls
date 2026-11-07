import Foundation
@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct JobsTests {
    private let home: TempHome
    private let jobs: JobStore

    init() throws {
        self.home = try TempHome()
        self.jobs = JobStore(directory: home.url.appending(path: "jobs"))
        // Prints, then waits in a child process, so stopping must end the whole process group.
        try home.write("waits.sh", "#!/bin/zsh\necho \"started $$\"\nsleep 30\necho never\n")
        try home.write("quick.sh", "#!/bin/zsh\necho done\n")
    }

    private func invocation(_ id: String) throws -> Invocation {
        let library = Library.load(home: home.url)
        return try Invocation(ParamBinder.bind(#require(library.automation(id: id)), arguments: []))
    }

    /// Whether `job` stops within a few seconds: a signalled process takes a moment to go.
    private func stopped(_ job: JobStore.Job) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while job.isRunning, ContinuousClock.now < deadline {
            await Task.yield()
        }
        return !job.isRunning
    }

    @Test func aJobRunsDetachedUntilStopped() async throws {
        let (job, output) = try await jobs.start(invocation("waits"), id: "waits")
        defer { jobs.stop("waits") }
        #expect(output == "started \(job.pid)")
        #expect(jobs.running() == [job])
        #expect(jobs.stop("waits"))
        #expect(await stopped(job))
        #expect(jobs.running().isEmpty)
        // The job's sleep went with it.
        #expect(kill(-job.pid, 0) != 0)
    }

    @Test func startingAgainReplacesTheRunningJob() async throws {
        let first = try await jobs.start(invocation("waits"), id: "waits").job
        let second = try await jobs.start(invocation("waits"), id: "waits").job
        defer { jobs.stop("waits") }
        #expect(await stopped(first))
        #expect(jobs.running() == [second])
    }

    @Test func aJobThatEndsIsNoLongerListed() async throws {
        let (job, output) = try await jobs.start(invocation("quick"), id: "quick")
        #expect(output == "done")
        #expect(await stopped(job))
        #expect(jobs.running().isEmpty)
        #expect(!jobs.stop("quick"))
    }
}
