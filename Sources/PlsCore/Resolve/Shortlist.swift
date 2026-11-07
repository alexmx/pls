import NaturalLanguage

/// The automations most likely to be what a request asks for, by meaning. Routing a big library over every
/// automation got both slower and less accurate (59 automations: 60 of 73 requests right in 3.4s, against 67 in 1.9s
/// over the closest 10), while up to about 30 it made no difference; so only libraries above that are cut down.
public enum Shortlist {
    /// Libraries with more automations than this are shortlisted.
    public static let threshold = 30
    /// How many automations a shortlist keeps.
    public static let size = 10
    /// How many the fallback reads when nothing in the shortlist fits: enough to recover a near miss, few enough for
    /// the model's context however big the library gets (all of them took about 57 tokens each).
    public static let fallbackSize = 40

    /// The `size` automations whose description or examples are closest to `request` (see `closest`), or all of them
    /// when there are `threshold` or fewer. The sentence embedding is English only.
    static func candidates(for request: String, among automations: [Automation]) -> [Automation] {
        automations.count > threshold ? closest(size, to: request, among: automations) : automations
    }

    /// The `count` automations closest to `request`, in their original order; all of them when there are no more, or
    /// when the request is clearly in another language, or the embedding isn't available.
    static func closest(_ count: Int, to request: String, among automations: [Automation]) -> [Automation] {
        guard automations.count > count,
              !isClearlyNotEnglish(request),
              let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let wanted = embedding.vector(for: request)
        else { return automations }
        let distances = automations.map { automation in
            ([automation.description ?? ""] + automation.examples)
                .compactMap { embedding.vector(for: $0) }
                .map { cosineDistance(wanted, $0) }
                .min() ?? .infinity
        }
        let kept = Set(automations.indices.sorted { distances[$0] < distances[$1] }.prefix(count))
        return automations.indices.filter(kept.contains).map { automations[$0] }
    }

    /// Short requests are often misread ("show open PRs" as Indonesian, "toggle mute" as Turkish) but with little
    /// confidence, so only a confident guess of another language counts.
    static func isClearlyNotEnglish(_ request: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(request)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { return false }
        return language != .english && confidence > 0.5
    }

    private static func cosineDistance(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, normA = 0.0, normB = 0.0
        for (x, y) in zip(a, b) {
            dot += x * y
            normA += x * x
            normB += y * y
        }
        return 1 - dot / (normA.squareRoot() * normB.squareRoot())
    }
}
