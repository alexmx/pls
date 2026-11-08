import CryptoKit
import Foundation

/// A SHA-256 of exactly what an automation runs: its file, or every file in its folder, each with its path relative
/// to the folder, whether it's executable (that decides how pls runs a script) and its bytes. A symlink counts as its
/// target path; a collection's automation can only link within its own folder, so the target is hashed too. Approving
/// a collection's automation records this, so a change by any route turns it off again.
public enum Fingerprint {
    public static func of(_ automation: Automation) -> String {
        var hash = SHA256()
        for file in automation.files {
            let path = automation.relativePath(of: file)
            hash
                .update(
                    data: Data(
                        "\(path)\0\(FileManager.default.isExecutableFile(atPath: file.path) ? "x" : "-")\0"
                            .utf8
                    )
                )
            if isSymlink(file) {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) ?? ""
                hash.update(data: Data("link:\(target)\0".utf8))
            } else {
                let data = (try? Data(contentsOf: file)) ?? Data()
                hash.update(data: Data("\(data.count)\0".utf8))
                hash.update(data: data)
            }
        }
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
