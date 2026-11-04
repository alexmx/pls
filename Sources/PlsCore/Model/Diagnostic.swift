import Foundation

/// A problem found while loading or checking the library.
public struct Diagnostic: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        /// The automation can't be used.
        case error
        /// The automation works, but something is likely a mistake.
        case warning
    }

    public let severity: Severity
    public let message: String
    public var file: URL?
    public var line: Int?
    /// The automation the problem belongs to, when there is one (not for e.g. a missing library folder).
    public var automationID: String?

    public init(
        _ severity: Severity, _ message: String, file: URL? = nil, line: Int? = nil, automation: String? = nil
    ) {
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.automationID = automation
    }
}
