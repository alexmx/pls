import PlsCore

/// How one case went.
struct Verdict: Equatable {
    /// Whether the right automation was picked (or none, for a `none` case).
    let routed: Bool
    /// Expected values that came out missing or wrong, as `name=got (want …)`.
    let wrongValues: [String]
    /// Values the model filled that the case doesn't expect or allow, as `name=value`.
    let invented: [String]

    var passed: Bool {
        routed && wrongValues.isEmpty && invented.isEmpty
    }
}

/// Scores a resolved request. `picked` is the id resolved (nil for no match) and `values` the run's values with where
/// each came from, defaults included. Values are only checked when the pick is right.
func score(_ evalCase: EvalCase, picked: String?, values: [String: BoundValue]) -> Verdict {
    let routed = (picked ?? EvalCase.noMatch) == evalCase.expect
    guard routed, picked != nil else { return Verdict(routed: routed, wrongValues: [], invented: []) }

    let wrong = evalCase.values.sorted { $0.key < $1.key }.compactMap { name, expected -> String? in
        let got = values[name]?.value ?? ""
        return expected.accepts(got) ? nil : "\(name)=\(got.isEmpty ? "∅" : got) (want \(expected))"
    }
    let invented = values.filter { $0.value.source == .request }
        .filter { evalCase.values[$0.key] == nil && !evalCase.allow.contains($0.key) }
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value.value)" }
    return Verdict(routed: routed, wrongValues: wrong, invented: invented)
}
