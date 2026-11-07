@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AppleScriptErrorsTests {
    @Test(arguments: [
        (
            "/Users/me/x/set-wallpaper.applescript:374:400: execution error: No image at /x.jpg (1)",
            "No image at /x.jpg"
        ),
        ("6:13: execution error: plain (-2700)", "plain"),
        (
            "/a b/c.applescript:1:2: execution error: Can’t get item 1 of {} (it's empty). (-1728)",
            "Can’t get item 1 of {} (it's empty)."
        ),
        ("a log line", "a log line"),
        (
            "/x.applescript:2: error: Expected expression but found end of line. (-2741)",
            "/x.applescript:2: error: Expected expression but found end of line. (-2741)"
        )
    ])
    func keepsTheMessageOfAnExecutionError(line: String, shown: String) {
        #expect(AppleScriptErrors.cleaned(line) == shown)
    }
}
