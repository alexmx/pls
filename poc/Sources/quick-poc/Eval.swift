import Foundation

struct EvalFile: Decodable {
    struct PickCase: Decodable {
        let query: String
        let expect: String
        let params: [String: String]
    }
    let pick: [PickCase]
    let oneoff: [String]
    let create: [String]
}

struct Eval {
    let model: ModelChoice

    func run(only: String?) async throws {
        let file = try JSONDecoder().decode(EvalFile.self, from: Data(contentsOf: pocRoot.appending(path: "evals.json")))
        print("model: \(model.rawValue)\n")
        if only == nil || only == "pick" { try await pick(file.pick) }
        if only == nil || only == "oneoff" { try await oneOff(file.oneoff) }
        if only == nil || only == "create" { try await create(file.create) }
    }

    // MARK: pick & fill

    private func pick(_ cases: [EvalFile.PickCase]) async throws {
        let catalog = try Catalog.load()
        let picker = Picker(catalog: catalog, model: model)
        print("== PICK & FILL (\(cases.count) cases) ==")
        var routeOK = 0, paramsOK = 0, paramCases = 0
        var latencies: [Double] = []

        for c in cases {
            let r: PickResult
            do { r = try await picker.pick(c.query) } catch {
                print("✗ ERROR  \(c.query)\n    \(error)")
                continue
            }
            latencies.append(r.routeSeconds + r.fillSeconds)
            let routed = r.id == c.expect
            if routed { routeOK += 1 }

            var paramNote = ""
            if routed && !c.params.isEmpty {
                paramCases += 1
                let defaults = Dictionary(uniqueKeysWithValues: (catalog.automation(c.expect)?.allParams ?? []).compactMap { p in p.default.map { (p.name, $0) } })
                let wrong = c.params.filter { key, want in !matches(r.params[key] ?? defaults[key], want) }
                if wrong.isEmpty { paramsOK += 1 } else {
                    paramNote = "  params wrong: " + wrong.keys.sorted().map { "\($0)=\(r.params[$0] ?? "∅") (want \(c.params[$0]!))" }.joined(separator: ", ")
                }
            }
            let got = r.params.isEmpty ? "" : "  " + r.params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            let mark = routed && paramNote.isEmpty ? "✓" : "✗"
            print(String(format: "%@ %5.2fs  %-55@ → %@%@", mark, r.routeSeconds + r.fillSeconds, c.query as NSString,
                         (routed ? r.id : "\(r.id) (want \(c.expect))") as NSString, got as NSString) + paramNote)
        }

        let sorted = latencies.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        print("""

            routing:  \(routeOK)/\(cases.count) correct
            params:   \(paramsOK)/\(paramCases) correct (cases with expected params, routed correctly)
            latency:  median \(String(format: "%.2f", pct(0.5)))s · p90 \(String(format: "%.2f", pct(0.9)))s · max \(String(format: "%.2f", sorted.last ?? 0))s

            """)
    }

    private func matches(_ got: String?, _ want: String) -> Bool {
        guard let got else { return false }
        func norm(_ s: String) -> String {
            var s = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "'\"")))
            while s.hasSuffix("/") || s.hasSuffix("%") { s.removeLast() }
            return s
        }
        let g = norm(got), w = norm(want)
        if let gn = Double(g), let wn = Double(w) { return gn == wn }
        return g == w || g.contains(w)
    }

    // MARK: generation

    private func oneOff(_ tasks: [String]) async throws {
        print("== ONE-OFF COMMANDS (\(tasks.count)) — judge correctness by eye ==")
        var passed = 0
        for t in tasks {
            do {
                let (plan, secs) = try await timed { try await generateOneOff(t, model: model) }
                let c = check(script: plan.command, kind: "shell")
                if c.ok { passed += 1 }
                print(String(format: "%@ %5.2fs  %@", c.ok ? "✓" : "✗", secs, t))
                print("    $ \(plan.command)\(plan.destructive ? "   ⚠️" : "")")
                if !c.ok { print("    \(describe(c))") }
            } catch { print("✗ ERROR  \(t)\n    \(error)") }
        }
        print("\nstatic checks passed: \(passed)/\(tasks.count)\n")
    }

    private func create(_ requests: [String]) async throws {
        print("== CREATE AUTOMATION (\(requests.count)) — judge correctness by eye ==")
        var passed = 0
        for r in requests {
            do {
                let (d, secs) = try await timed { try await generateAutomation(r, model: model) }
                let c = check(script: d.script, kind: d.kind)
                if c.ok { passed += 1 }
                print(String(format: "%@ %5.2fs  %@", c.ok ? "✓" : "✗", secs, r))
                print("    \(d.id) · \(d.kind) · params: \(d.params.map { "\($0.name):\($0.type)" }.joined(separator: ", "))")
                print(d.script.split(separator: "\n", omittingEmptySubsequences: false).map { "    | \($0)" }.joined(separator: "\n"))
                if !c.ok { print("    \(describe(c))") }
            } catch { print("✗ ERROR  \(r)\n    \(error)") }
        }
        print("\nstatic checks passed: \(passed)/\(requests.count)\n")
    }
}
