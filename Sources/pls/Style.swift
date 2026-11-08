import Foundation

/// Bold, dim and color for text shown in a terminal; plain text when it's off.
struct Style {
    let isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }

    /// On when `descriptor` is a terminal and `NO_COLOR` isn't set to anything (no-color.org).
    init(for descriptor: Int32, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.isOn = isatty(descriptor) != 0 && (environment["NO_COLOR"] ?? "").isEmpty
    }

    func bold(_ text: String) -> String {
        wrap(text, "1")
    }

    func dim(_ text: String) -> String {
        wrap(text, "2")
    }

    func yellow(_ text: String) -> String {
        wrap(text, "33")
    }

    private func wrap(_ text: String, _ code: String) -> String {
        isOn && !text.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }
}
