import Foundation

/// Folder holding catalog.json / evals.json (the package root).
let pocRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct Catalog: Decodable {
    let automations: [Automation]

    static func load() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: pocRoot.appending(path: "catalog.json")))
    }

    func automation(_ id: String) -> Automation? { automations.first { $0.id == id } }

    /// Compact listing the router sees. Kept small: the on-device context is ~4K tokens.
    var routingListing: String {
        automations.map { a in
            var line = "- \(a.id): \(a.description)"
            if let ex = a.examples, !ex.isEmpty { line += " (e.g. \(ex.map { "\"\($0)\"" }.joined(separator: ", ")))" }
            return line
        }.joined(separator: "\n")
    }
}

struct Automation: Decodable {
    let id: String
    let name: String
    let description: String
    let kind: String
    let examples: [String]?
    let params: [Param]?
    let run: String

    var allParams: [Param] { params ?? [] }

    /// Fills `{{name}}` placeholders, using defaults for anything not extracted.
    func render(_ values: [String: String]) -> String {
        allParams.reduce(run) { cmd, p in
            cmd.replacingOccurrences(of: "{{\(p.name)}}", with: values[p.name] ?? p.default ?? "<missing \(p.name)>")
        }
    }
}

struct Param: Decodable {
    enum Kind: String, Decodable { case string, path, int, number, bool, `enum` }
    let name: String
    let type: Kind
    let description: String
    let `default`: String?
    let options: [String]?
    let min: Int?
    let max: Int?
}
