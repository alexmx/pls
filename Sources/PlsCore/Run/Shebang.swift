import Foundation

enum Shebang {
    /// The `#!` line of `script` split into program and arguments, e.g. `["/usr/bin/env", "python3"]`; nil when there's
    /// no shebang or it names no program. Such a script runs with zsh.
    static func read(_ script: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: script) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512),
              let firstLine = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first,
              firstLine.hasPrefix("#!")
        else { return nil }
        let words = firstLine.dropFirst(2).split(whereSeparator: \.isWhitespace).map(String.init)
        return words.isEmpty ? nil : words
    }
}
