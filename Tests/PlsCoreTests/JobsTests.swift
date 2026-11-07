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

    @Test func aJobRunsDetachedUntilStopped() async throws {
        let (job, output) = try await jobs.start(invocation("waits"), id: "waits")
        defer { jobs.stop("waits") }
        #expect(output == "started \(job.pid)")
        #expect(jobs.running() == [job])
        #expect(jobs.stop("waits"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(!job.isRunning)
        #expect(jobs.running().isEmpty)
        // The job's sleep went with it.
        #expect(kill(-job.pid, 0) != 0)
    }

    @Test func startingAgainReplacesTheRunningJob() async throws {
        let first = try await jobs.start(invocation("waits"), id: "waits").job
        let second = try await jobs.start(invocation("waits"), id: "waits").job
        defer { jobs.stop("waits") }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!first.isRunning)
        #expect(jobs.running() == [second])
    }

    @Test func aJobThatEndsIsNoLongerListed() async throws {
        let (job, output) = try await jobs.start(invocation("quick"), id: "quick")
        #expect(output == "done")
        try await Task.sleep(for: .milliseconds(200))
        #expect(!job.isRunning)
        #expect(jobs.running().isEmpty)
        #expect(!jobs.stop("quick"))
    }
}
