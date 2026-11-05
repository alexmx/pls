/// Ranks automations by the words a request shares with their id, name, description and examples (SPEC §7): the
/// suggestions when the model finds no match, and the fallback when it can't be used. Plain word matching, so the same
/// request against the same library always gives the same answer.
public enum FuzzyMatcher {
    /// The automations sharing the most words with `request`, best first (ties by id); none if nothing is shared.
    public static func closest(to request: String, in automations: [Automation], limit: Int = 3) -> [Automation] {
        let requestWords = Set(words(request))
        guard !requestWords.isEmpty else { return [] }
        let scored = automations.map { automation in
            let automationWords = Set(words(([automation.id, automation.name, automation.description ?? ""]
                    + automation.examples).joined(separator: " ")))
            let score = requestWords.reduce(0.0) { total, word in
                total + (automationWords.map { similarity(word, $0) }.max() ?? 0)
            }
            return (automation, score)
        }
        return scored.filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
            .prefix(limit)
            .map(\.0)
    }

    /// Words too common to say anything about what a request wants, including the verbs most requests start with.
    private static let filler: Set<String> = [
        "a", "an", "and", "are", "at", "be", "can", "do", "for", "from", "get", "i", "in", "is", "it", "its", "make",
        "me", "my", "of", "on", "or", "please", "pls", "so", "some", "that", "the", "this", "to", "with", "you", "your"
    ]

    /// Lowercase runs of letters and digits, without filler words and single letters (the "s" of "it's").
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !filler.contains($0) }
    }

    /// 1 for the same word; ½ when both start the same way for 4 letters or all of the shorter one, if that has at
    /// least 3 ("dark" / "darker", "compress" / "compressing"); otherwise 0.
    private static func similarity(_ a: String, _ b: String) -> Double {
        if a == b {
            return 1
        }
        let shared = zip(a, b).prefix { $0 == $1 }.count
        let shorter = min(a.count, b.count)
        return shorter >= 3 && shared >= min(4, shorter) ? 0.5 : 0
    }
}
