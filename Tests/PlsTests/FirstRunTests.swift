import Testing

/// What someone sees right after installing, with no automations yet: where to start.
@Suite(.timeLimit(.minutes(1)))
struct FirstRunTests {
    private let pls: BuiltPls

    init() throws {
        self.pls = try BuiltPls()
    }

    @Test func listSaysWhereToStart() async throws {
        let list = try await pls.run("list")
        #expect(list.status == 0)
        #expect(list.stdout.hasSuffix(
            ", or install everyday ones to start with: `pls collection add alexmx/pls-automations`\n"
        ))
    }

    @Test func doctorSaysWhereToStart() async throws {
        let doctor = try await pls.run("doctor")
        #expect(doctor.status == 0)
        #expect(doctor.stdout.contains(
            "\nNo automations yet; install everyday ones to start with: `pls collection add alexmx/pls-automations`\n"
        ))
    }
}
