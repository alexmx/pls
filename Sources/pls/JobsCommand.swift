import ArgumentParser
import Foundation
import PlsCore

struct JobsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jobs",
        abstract: "List the automations running in the background, or stop one.",
        subcommands: [List.self, Stop.self],
        defaultSubcommand: List.self
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the automations running in the background.")

        func run() {
            let jobs = JobStore().running()
            guard !jobs.isEmpty else {
                print("No automations are running in the background.")
                return
            }
            let rows = jobs.map { job in
                [job.id, "since " + job.started.formatted(date: .omitted, time: .shortened), "pid \(job.pid)"]
            }
            table(rows).forEach { print($0) }
        }
    }

    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop an automation running in the background, and everything it started."
        )

        @Argument(
            help: "The automation's id.",
            completion: .custom { _, _, _ in JobStore().running().map(\.id) }
        )
        var id: String

        func run() {
            print(JobStore().stop(id) ? "Stopped \(id)." : "\(id) isn't running in the background.")
        }
    }
}
