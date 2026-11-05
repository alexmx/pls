import Foundation
import PlsCore

/// `xc evals`: resolves every request in `Evals/cases.yaml` against `Evals/library` with the on-device model, exactly
/// as `pls "<request>"` does, and reports how it went. An optional argument runs only the cases whose request contains
/// it. Exits 1 if a case failed, 2 if the model can't be used.
@main
enum PlsEvals {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func main() async throws {
        var cases = try EvalCase.load(root.appending(path: "cases.yaml"))
        if let filter = CommandLine.arguments.dropFirst().first {
            cases = cases.filter { $0.request.localizedCaseInsensitiveContains(filter) }
        }
        let library = Library.load(home: root.appending(path: "library"))
        guard library.diagnostics.allSatisfy({ $0.severity != .error }) else {
            print("The eval library has problems; run `PLS_HOME=Evals/library pls doctor`.")
            exit(2)
        }

        print("pls \(Pls.version) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(cases.count) cases\n")
        var verdicts: [Verdict] = []
        var seconds: [Double] = []
        for evalCase in cases {
            let start = ContinuousClock.now
            let binding: Binding?
            do {
                binding = try await NLResolver().resolve(evalCase.request, in: library)
            } catch let .unavailable(reason) {
                print("The model can't be used: \(reason)")
                exit(2)
            } catch {
                print("✗ \(evalCase.request)\n    \(error)")
                verdicts.append(Verdict(routed: false, wrongValues: [], invented: []))
                continue
            }
            let elapsed = (ContinuousClock.now - start) / .seconds(1)
            seconds.append(elapsed)

            let bound = binding?.values ?? [:]
            let values = bound.mapValues(\.value)
            let fromRequest = Set(bound.filter { $0.value.source == .request }.keys)
            let verdict = score(evalCase, picked: binding?.automation.id, values: values, fromRequest: fromRequest)
            verdicts.append(verdict)
            print(line(
                evalCase,
                picked: binding?.automation.id,
                values: values,
                fromRequest: fromRequest,
                verdict: verdict,
                seconds: elapsed
            ))
        }

        print("\n" + summary(cases, verdicts, seconds: seconds))
        if !verdicts.allSatisfy(\.passed) {
            exit(1)
        }
    }

    /// `✓ 1.32s  compress the pngs on my desktop… → compress-images  quality=60 format=png`, plus what went wrong.
    static func line(
        _ evalCase: EvalCase, picked: String?, values: [String: String], fromRequest: Set<String>, verdict: Verdict,
        seconds: Double
    ) -> String {
        let pick = picked ?? EvalCase.noMatch
        let filled = fromRequest.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: " ")
        var text = "\(verdict.passed ? "✓" : "✗") \(String(format: "%5.2fs", seconds))  \(evalCase.request) → "
            + (verdict.routed ? pick : "\(pick) (want \(evalCase.expect))")
            + (filled.isEmpty ? "" : "  \(filled)")
        if !verdict.wrongValues.isEmpty {
            text += "\n      wrong: " + verdict.wrongValues.joined(separator: ", ")
        }
        if !verdict.invented.isEmpty {
            text += "\n      invented: " + verdict.invented.joined(separator: ", ")
        }
        return text
    }

    /// Pass count, then routing, values (cases routed right that expect values) and invented values, then latency.
    static func summary(_ cases: [EvalCase], _ verdicts: [Verdict], seconds: [Double]) -> String {
        let routed = zip(cases, verdicts).filter { $0.1.routed }
        let withValues = routed.filter { !$0.0.values.isEmpty }
        let sorted = seconds.sorted()
        func percentile(_ fraction: Double) -> Double {
            sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
        }
        return """
        passed    \(verdicts.filter(\.passed).count)/\(cases.count)
        routing   \(routed.count)/\(cases.count) picked right
        values    \(withValues.filter { $0.1.wrongValues.isEmpty }.count)/\(withValues.count) right \
        (cases picked right that expect values)
        invented  \(routed.filter { !$0.1.invented.isEmpty }.count) cases filled a value the request didn't give
        latency   median \(String(format: "%.2f", percentile(0.5)))s · p90 \(String(format: "%.2f", percentile(0.9)))s \
        · max \(String(format: "%.2f", sorted.last ?? 0))s
        """
    }
}
