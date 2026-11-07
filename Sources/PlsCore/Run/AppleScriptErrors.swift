/// `osascript` reports an AppleScript error as `<file>:374:400: execution error: No image at /x.jpg (1)`: a character
/// range and an error number around the message the script raised. Runner passes on just the message.
enum AppleScriptErrors {
    /// The message of an `execution error` line; any other line unchanged.
    static func cleaned(_ line: String) -> String {
        guard let match = line.wholeMatch(of: /(?:.*?:)?\d+:\d+: execution error: (.*?)(?: \(-?\d+\))?/) else {
            return line
        }
        return String(match.1)
    }
}
