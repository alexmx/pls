import Subprocess

extension Environment {
    /// Exactly `variables`, nothing else inherited: callers have already merged in what they pass on.
    static func exactly(_ variables: [String: String]) -> Self {
        .custom(Dictionary(uniqueKeysWithValues: variables.compactMap { key, value in
            Key(rawValue: key).map { ($0, value) }
        }))
    }
}

extension TerminationStatus {
    /// The exit code, or 128 + the signal number if a signal ended it, as shells report it.
    var shellCode: Int32 {
        switch self {
        case let .exited(code): code
        case let .signaled(signal): 128 + signal
        }
    }
}
