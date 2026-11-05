import Foundation
import Yams

/// One request from `Evals/cases.yaml` and what resolving it should give (the file's header explains the format).
struct EvalCase: Decodable, Equatable {
    /// What an expected value may be.
    enum Expected: Decodable, Equatable, CustomStringConvertible {
        /// Any non-empty value (`"*"`): the request implies one but leaves its wording open.
        case any
        /// One of these, compared after `normalized`.
        case oneOf([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([String].self) {
                self = .oneOf(list)
            } else {
                let value = try container.decode(String.self)
                self = value == "*" ? .any : .oneOf([value])
            }
        }

        var description: String {
            switch self {
            case .any: "any value"
            case let .oneOf(options): options.joined(separator: " or ")
            }
        }

        func accepts(_ value: String) -> Bool {
            switch self {
            case .any: !value.isEmpty
            case let .oneOf(options): options.contains { normalized($0) == normalized(value) }
            }
        }
    }

    static let noMatch = "none"

    let request: String
    /// The id the request should pick, or `noMatch`.
    let expect: String
    let values: [String: Expected]
    /// Params the model may fill without it counting as invented.
    let allow: [String]

    private enum CodingKeys: String, CodingKey {
        case request, expect, values, allow
    }

    init(request: String, expect: String, values: [String: Expected] = [:], allow: [String] = []) {
        self.request = request
        self.expect = expect
        self.values = values
        self.allow = allow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.request = try container.decode(String.self, forKey: .request)
        self.expect = try container.decode(String.self, forKey: .expect)
        self.values = try container.decodeIfPresent([String: Expected].self, forKey: .values) ?? [:]
        self.allow = try container.decodeIfPresent([String].self, forKey: .allow) ?? []
    }

    static func load(_ file: URL) throws -> [EvalCase] {
        try YAMLDecoder().decode([EvalCase].self, from: String(contentsOf: file, encoding: .utf8))
    }
}

/// Lowercased, without surrounding spaces and quotes or a trailing `/` or `%`. Numbers need nothing more: bound int
/// values are whole numbers, and the model's numbers come without a trailing `.0` (`NLResolver.values(in:)`).
func normalized(_ value: String) -> String {
    var text = value.lowercased().trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "'\"")))
    while text.hasSuffix("/") || text.hasSuffix("%") {
        text.removeLast()
    }
    return text
}
