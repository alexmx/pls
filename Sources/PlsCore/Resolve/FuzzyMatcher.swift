/// Ranks automations by the words a request shares with their id, name, description and examples: the
/// suggestions when the model finds no match, and the fallback when it can't be used. Plain word matching, so the same
/// request against the same library always gives the same answer.
public enum FuzzyMatcher {
    /// The automations sharing the most words with `request`, best first (ties by id); none if nothing is shared.
    public static func closest(to request: String, in automations: [Automation], limit: Int = 3) -> [Automation] {
        let requestWords = Set(words(request))
        guard !requestWords.isEmpty else { return [] }
        let scored = automations.map { automation -> (automation: Automation, score: Double) in
            let automationWords = Set(words(([automation.id, automation.name, automation.description ?? ""]
                    + automation.examples).joined(separator: " ")))
            let score = requestWords.reduce(0.0) { total, word in
                total + (automationWords.map { similarity(word, $0) }.max() ?? 0)
            }
            return (automation, score)
        }
        return scored.filter { $0.score > 0 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.automation.id < $1.automation.id }
            .prefix(limit)
            .map(\.automation)
    }

    /// Words too common to say anything about what a request wants: articles, pronouns, question words and the verbs
    /// most requests start with.
    private static let filler: Set<String> = [
        "a", "an", "and", "are", "at", "be", "can", "could", "do", "does", "for", "from", "get", "how", "i", "in", "is",
        "it", "its", "make", "me", "my", "of", "on", "or", "please", "pls", "should", "so", "some", "that", "the",
        "this", "to", "what", "when", "where", "which", "who", "why", "will", "with", "would", "you", "your"
    ]

    /// Lowercase runs of letters and digits, without filler words and single letters (the "s" of "it's").
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !filler.contains($0) }
    }

    /// 1 for the same word; ½ when both start with the same 4 letters ("dark" / "darker", "compress" /
    /// "compressing"); otherwise 0. Three letters say too little: "app" isn't "appearance".
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b {
            return 1
        }
        return zip(a, b).prefix { $0 == $1 }.count >= 4 ? 0.5 : 0
    }
}
