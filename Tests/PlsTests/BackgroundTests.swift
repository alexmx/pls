import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct BackgroundTests {
    private let pls: BuiltPls

    init() throws {
        self.pls = try BuiltPls()
        try pls.write("waits.sh", """
        #!/bin/zsh
        # @pls.description: Wait in the background
        # @pls.background: true
        echo "waiting"
        sleep 30
        """)
    }

    /// pls returns at once with the job's first line, lists it, and stops it.
    @Test func aBackgroundAutomationRunsUntilStopped() async throws {
        let clock = ContinuousClock.now
        let started = try await pls.run("run", "waits")
        #expect(ContinuousClock.now - clock < .seconds(5))
        #expect(started.status == 0)
        #expect(started.stdout == "waiting\n")
        #expect(started.stderr.contains("pls jobs stop waits"))

        #expect(try await pls.run("jobs").stdout.hasPrefix("waits  since "))
        #expect(try await pls.run("jobs", "stop", "waits").stdout == "Stopped waits.\n")
        #expect(try await pls.run("jobs").stdout == "No automations are running in the background.\n")
    }
}
