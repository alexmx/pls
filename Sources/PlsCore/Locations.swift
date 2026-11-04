import Foundation

/// Where pls keeps things (SPEC §2): `$PLS_HOME` when set, so a test library is self-contained; otherwise the XDG
/// folder for that kind of file.
enum Locations {
    /// `$PLS_HOME`, else `$<xdgVariable>/pls`, else `~/<fallback>/pls`.
    static func directory(xdgVariable: String, fallback: String, environment: [String: String]) -> URL {
        func expanded(_ path: String) -> URL {
            URL(filePath: (path as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        if let path = environment["PLS_HOME"], !path.isEmpty {
            return expanded(path)
        }
        if let base = environment[xdgVariable], !base.isEmpty {
            return expanded(base).appending(path: "pls", directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: fallback, directoryHint: .isDirectory)
            .appending(path: "pls", directoryHint: .isDirectory)
    }
}
