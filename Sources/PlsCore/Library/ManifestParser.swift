import Foundation
import Yams

/// Reads `manifest.yaml` of a folder automation. Diagnostics carry the YAML line but no file.
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
        if let node = reader.confirmNode,
           let problem = reader.result.metadata.confirm.problem(with: reader.result.metadata.params) {
            reader.error(problem, at: node)
        }
        if mapping["entry"] == nil {
            reader.error("missing entry (the script file to run)", at: root)
        }
        return reader.result
    }

    private struct Reader {
        var result = Result()
        /// Where `confirm` was, to report a mismatch with the params, which are read after it or before.
        var confirmNode: Node?

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
                    guard let confirm = confirmation(value) else {
                        error("confirm must be true, false or a mapping like {action: [shutdown, restart]}", at: value)
                        continue
                    }
                    result.metadata.confirm = confirm
                    confirmNode = value
                case "preview":
                    guard let flag = strictBool(value) else {
                        error("preview must be true or false", at: value)
                        continue
                    }
                    result.metadata.preview = flag
                case "background":
                    guard let flag = strictBool(value) else {
                        error("background must be true or false", at: value)
                        continue
                    }
                    result.metadata.background = flag
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
                do {
                    try result.metadata.add(param)
                } catch {
                    self.error(error.description, at: item)
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
                let requirement = try Param.Requirement(
                    param: name, isOptional: isOptional, defaultValue: defaultValue
                )
                let description = fields["description"].flatMap { text($0, "description") }
                return try Param(name: name, type: type, requirement: requirement, description: description)
            } catch {
                self.error(error.description, at: node)
                return nil
            }
        }

        func paramType(_ name: String, _ fields: [String: Node]) throws(ParamError) -> ParamType {
            let bounds: (min: String, max: String)?
            switch (fields["min"], fields["max"]) {
            case (nil, nil): bounds = nil
            case let (min?, max?): bounds = (scalarText(min), scalarText(max))
            default: throw ParamError("give both min and max, or neither")
            }
            // A non-list or a non-text item becomes "", which the shared rules reject.
            let options = fields["options"].map { node in node.sequence?.map(scalarText) ?? [""] }
            return try ParamType(name: name, bounds: bounds, options: options)
        }

        /// The node's text if it's a non-null scalar, otherwise "".
        func scalarText(_ node: Node) -> String {
            node.scalar != nil && node.null == nil ? node.string ?? "" : ""
        }

        static let paramKeys: Set = ["name", "type", "default", "optional", "description", "min", "max", "options"]

        // MARK: helpers

        /// `true`, `false`, or one param mapped to a choice or a list of them: `{action: [shutdown, restart]}`.
        func confirmation(_ node: Node) -> Confirmation? {
            if let flag = strictBool(node) {
                return flag ? .always : .never
            }
            guard let mapping = node.mapping, mapping.count == 1, let (key, value) = mapping.first,
                  let param = key.string else { return nil }
            let choices = value.sequence.map { $0.map(scalarText) } ?? [scalarText(value)]
            guard !choices.isEmpty, !choices.contains("") else { return nil }
            return .when(param: param, choices: choices)
        }

        /// Only `true` / `false`, as in headers; YAML's `yes` / `on` are not accepted.
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
