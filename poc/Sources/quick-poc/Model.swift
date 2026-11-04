import Foundation
import FoundationModels

enum ModelChoice: String {
    case local  // on-device SystemLanguageModel
    case pcc    // Private Cloud Compute model

    func session(instructions: String) -> LanguageModelSession {
        switch self {
        case .local: LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        case .pcc: LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
        }
    }
}

let deterministic = GenerationOptions(samplingMode: .greedy)

/// Runs `body` and returns its result plus elapsed seconds.
func timed<T>(_ body: () async throws -> T) async rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let value = try await body()
    let d = ContinuousClock.now - start
    return (value, Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
}

/// Flattens a structured GeneratedContent into name → display string.
func flatten(_ content: GeneratedContent) -> [String: String] {
    guard case let .structure(props, keys) = content.kind else { return [:] }
    var out: [String: String] = [:]
    for key in keys {
        guard let v = props[key] else { continue }
        switch v.kind {
        case .null: continue
        case .string(let s): out[key] = s
        case .bool(let b): out[key] = String(b)
        case .number(let n): out[key] = n.rounded() == n ? String(Int(n)) : String(n)
        default: out[key] = v.jsonString
        }
    }
    return out
}
