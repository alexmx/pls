@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct EscapingTests {
    @Test(arguments: [
        ("plain", false), ("with space", false), ("", false), ("é ✓", false),
        ("a\nb", true), ("a\tb", true), ("a\rb", true), ("\u{1B}[0m", true), ("a\u{2028}b", true), ("\u{85}", true)
    ])
    func needsEscaping(value: String, expected: Bool) {
        #expect(Escaping.needsEscaping(value) == expected)
    }

    @Test(arguments: [
        ("", #""""#),
        ("a b", #""a b""#),
        ("a\nb\tc\rd", #""a\nb\tc\rd""#),
        (#"say "hi" \o/"#, #""say \"hi\" \\o/""#),
        ("\u{1B}[0m", #""\x1B[0m""#),
        ("a\u{2028}b", #""a\u2028b""#),
        ("it's", #""it's""#)
    ])
    func quoted(value: String, expected: String) {
        #expect(Escaping.quoted(value) == expected)
    }

    @Test(arguments: [
        ("plain", "plain"),
        ("it's here", #"'it'\''s here'"#),
        ("", "''"),
        ("a\nb", #"$'a\nb'"#),
        ("it's\t\\", #"$'it\'s\t\\'"#),
        ("\"\n", #"$'"\n'"#)
    ])
    func shellQuoted(value: String, expected: String) {
        #expect(Invocation.shellQuoted(value) == expected)
    }
}
