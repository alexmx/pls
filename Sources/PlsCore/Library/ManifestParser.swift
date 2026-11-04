import Foundation
import Yams

/// Reads `manifest.yaml` of a folder automation (SPEC §3.2). Diagnostics carry the YAML line but no file.
public enum ManifestParser {
    public struct Result: Sendable, Equatable {
        public var metadata = Metadata()
        /// The script file inside the folder, as written in the manifest.
        public var entry: String?
        /// Set only when the manifest overrides the kind inferred from `entry`.
        public var kind: AutomationKind?
        public var diagnostics: [Diagnostic] = []
    }

    public static func parse(_ text: String) -> Result {
        var reader = Reader()
        let root: Node?
        do {
            root = try Yams.compose(yaml: text)
        } catch {
            let detail = "\(error)".split(separator: "\n").first.map(String.init) ?? "\(error)"
            reader.result.diagnostics.append(Diagnostic(.error, "invalid YAML: \(detail)"))
            return reader.result
        }
        guard let mapping = root?.mapping else {
            reader.error("manifest must be a YAML mapping of keys like name, description, entry", at: root)
            return reader.result
        }
        reader.readTopLevel(mapping)
        if mapping["entry"] == nil {
            reader.error("missing entry (the script file to run)", at: root)
        }
        return reader.result
    }

    private struct Reader {
        var result = Result()

        mutating func readTopLevel(_ mapping: Node.Mapping) {
            for (keyNode, value) in mapping {
                let key = keyNode.string ?? ""
                switch key {
                case "name": result.metadata.name = text(value, key)
                case "description": result.metadata.description = text(value, key)
                case "entry": result.entry = text(value, key)
                case "kind":
                    guard let raw = text(value, key) else { continue }
                    guard let kind = AutomationKind(rawValue: raw) else {
                        error("kind must be shell or applescript", at: value)
                        continue
                    }
                    result.kind = kind
                case "confirm":
                    guard let flag = strictBool(value) else {
                        error("confirm must be true or false", at: value)
                        continue
                    }
                    result.metadata.confirm = flag
                case "examples": result.metadata.examples = texts(value, key) ?? []
                case "params": readParams(value)
                default: warning("unknown key \(key)", at: keyNode)
                }
            }
        }

        mutating func readParams(_ node: Node) {
            guard let sequence = node.sequence else {
                error("params must be a list", at: node)
                return
            }
            for item in sequence {
                guard let mapping = item.mapping else {
                    error("each param must be a mapping with name and type", at: item)
                    continue
                }
                guard let param = readParam(mapping, at: item) else { continue }
                if result.metadata.params.contains(where: { $0.name == param.name }) {
                    error("param \"\(param.name)\" is declared twice", at: item)
                } else {
                    result.metadata.params.append(param)
                }
            }
        }

        mutating func readParam(_ mapping: Node.Mapping, at node: Node) -> Param? {
            var fields: [String: Node] = [:]
            for (keyNode, value) in mapping {
                let key = keyNode.string ?? ""
                if Self.paramKeys.contains(key) {
                    fields[key] = value
                } else {
                    warning("unknown param key \(key)", at: keyNode)
                }
            }
            guard let name = fields["name"].flatMap({ text($0, "name") }) else {
                if fields["name"] == nil {
                    error("param is missing name", at: node)
                }
                return nil
            }
            guard let typeName = fields["type"].flatMap({ text($0, "type") }) else {
                if fields["type"] == nil {
                    error("param \(name) is missing type", at: node)
                }
                return nil
            }
            do throws(ParamError) {
                let type = try paramType(typeName, fields)
                var defaultValue: String?
                if let node = fields["default"] {
                    guard node.scalar != nil, node.null == nil, let value = node.string else {
                        throw ParamError("default for \(name) must be a single value; use \"\" for empty text")
                    }
                    defaultValue = value
                }
                var isOptional = false
                if let node = fields["optional"] {
                    guard let flag = strictBool(node) else {
                        throw ParamError("optional must be true or false")
                    }
                    isOptional = flag
                }
                let requirement: Param.Requirement
                switch (isOptional, defaultValue) {
                case (true, .some): throw ParamError("param \(name) is optional and also has a default; use one")
                case (true, .none): requirement = .optional
                case let (false, .some(value)): requirement = .defaultValue(value)
                case (false, .none): requirement = .required
                }
                let description = fields["description"].flatMap { text($0, "description") }
                return try Param(name: name, type: type, requirement: requirement, description: description)
            } catch {
                self.error(error.description, at: node)
                return nil
            }
        }

        func paramType(_ name: String, _ fields: [String: Node]) throws(ParamError) -> ParamType {
            let min = fields["min"], max = fields["max"], options = fields["options"]
            switch name {
            case "string", "path", "bool":
                guard min == nil, max == nil, options == nil else {
                    throw ParamError("\(name) doesn't take min, max or options")
                }
                return name == "string" ? .string : name == "path" ? .path : .bool
            case "int", "number":
                guard options == nil else { throw ParamError("\(name) doesn't take options") }
                guard let min, let max else {
                    if min == nil, max == nil {
                        return name == "int" ? .int(nil) : .number(nil)
                    }
                    throw ParamError("give both min and max, or neither")
                }
                if name == "int" {
                    guard let lo = min.int, let hi = max.int, lo <= hi else {
                        throw ParamError("int min and max must be whole numbers with min <= max")
                    }
                    return .int(lo...hi)
                }
                guard let lo = min.float, let hi = max.float, lo <= hi else {
                    throw ParamError("number min and max must be numbers with min <= max")
                }
                return .number(lo...hi)
            case "enum":
                guard min == nil, max == nil else { throw ParamError("enum doesn't take min or max") }
                let values = options?.sequence?.compactMap { $0.null == nil ? $0.string : nil } ?? []
                guard !values.isEmpty, values.count == options?.sequence?.count, Set(values).count == values.count
                else {
                    throw ParamError("enum needs a list of distinct options")
                }
                return .enum(values)
            default:
                throw ParamError("unknown type \"\(name)\"; use string, path, int, number, bool or enum")
            }
        }

        static let paramKeys: Set = ["name", "type", "default", "optional", "description", "min", "max", "options"]

        // MARK: helpers

        /// Only `true` / `false`, as in headers (SPEC §4.1); YAML's `yes` / `on` are not accepted.
        func strictBool(_ node: Node) -> Bool? {
            switch node.scalar?.string {
            case "true": true
            case "false": false
            default: nil
            }
        }

        mutating func text(_ node: Node, _ key: String) -> String? {
            guard node.scalar != nil, node.null == nil, let value = node.string, !value.isEmpty else {
                error("\(key) must be non-empty text", at: node)
                return nil
            }
            return value
        }

        mutating func texts(_ node: Node, _ key: String) -> [String]? {
            guard let sequence = node.sequence else {
                error("\(key) must be a list", at: node)
                return nil
            }
            return sequence.compactMap { text($0, key) }
        }

        mutating func error(_ message: String, at node: Node?) {
            result.diagnostics.append(Diagnostic(.error, message, line: node?.mark?.line))
        }

        mutating func warning(_ message: String, at node: Node?) {
            result.diagnostics.append(Diagnostic(.warning, message, line: node?.mark?.line))
        }
    }
}
