import Foundation
import FoundationModels

/// Natural language → a binding, with Apple's on-device model (SPEC §7). Two stages: route the request to one
/// automation, then fill that automation's params. Both use greedy sampling and a fresh session, so the same request
/// against the same library gets the same answer.
public struct NLResolver: Sendable {
    public enum ModelError: Error, Equatable, CustomStringConvertible {
        /// The model can't be used on this Mac right now.
        case unavailable(String)
        /// The model was asked but couldn't answer.
        case failed(String)

        public var description: String {
            switch self {
            case let .unavailable(reason), let .failed(reason): reason
            }
        }
    }

    private let model: SystemLanguageModel
    private let environment: [String: String]

    /// `PLS_MODEL=off` in `environment` turns the model off, so requests use word matching instead.
    public init(
        model: SystemLanguageModel = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.model = model
        self.environment = environment
    }

    /// The binding for `request`, or nil if no automation in `library` does what it asks.
    public func resolve(_ request: String, in library: Library) async throws(ModelError) -> Binding? {
        if let reason = Self.unavailableReason(model.availability, environment: environment) {
            throw .unavailable(reason)
        }
        let candidates = Self.candidates(in: library)
        guard !candidates.isEmpty else { return nil }
        do {
            guard let automation = try await route(request, among: candidates) else { return nil }
            let values = automation.params.isEmpty ? [:] : try await fill(request, for: automation)
            return ParamBinder.bind(automation, request: request, values: values)
        } catch let LanguageModelSession.GenerationError.exceededContextWindowSize(context) {
            throw .failed("""
            the request and the \(candidates.count) automations offered don't fit in the model's context \
            (\(context.debugDescription))
            """)
        } catch {
            throw .failed("the model couldn't answer: \(error.localizedDescription)")
        }
    }

    /// Why the model can't be used, or nil if it can.
    public static func unavailableReason(
        _ availability: SystemLanguageModel.Availability, environment: [String: String] = [:]
    ) -> String? {
        if environment["PLS_MODEL"] == "off" {
            return "Apple's on-device model is turned off (PLS_MODEL=off)"
        }
        return switch availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "this Mac can't run Apple's on-device model"
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence is off; turn it on in System Settings → Apple Intelligence & Siri"
        case .unavailable(.modelNotReady): "Apple's on-device model is still downloading; try again later"
        case .unavailable: "Apple's on-device model isn't available"
        }
    }

    // MARK: route

    /// Only automations with a description are offered: an id alone says too little to route on.
    static func candidates(in library: Library) -> [Automation] {
        library.automations.filter { $0.description != nil }
    }

    /// One line per automation: `- id: description (e.g. "example", …)`.
    static func routingList(_ automations: [Automation]) -> String {
        automations.map { automation in
            var line = "- \(automation.id): \(automation.description ?? "")"
            if !automation.examples.isEmpty {
                line += " (e.g. \(automation.examples.map { "\"\($0)\"" }.joined(separator: ", ")))"
            }
            return line
        }.joined(separator: "\n")
    }

    /// Uppercase, so no id can be it: ids are lowercase kebab-case, and `none` is a valid one.
    private static let noMatch = "NONE"

    private func route(_ request: String, among candidates: [Automation]) async throws -> Automation? {
        let ids = candidates.map(\.id) + [Self.noMatch]
        let root = DynamicGenerationSchema(name: "Route", properties: [
            .init(
                name: "automation",
                description: "id of the automation that does what the user asked, or \(Self.noMatch)",
                schema: DynamicGenerationSchema(name: "AutomationID", anyOf: ids)
            )
        ])
        let session = LanguageModelSession(model: model, instructions: """
        You route a user's request to one of their saved automations.
        Pick the automation whose purpose matches the request. \
        If no automation can do what the user asked, answer "\(Self.noMatch)". Do not guess.
        """)
        let response = try await session.respond(
            to: "Automations:\n\(Self.routingList(candidates))\n\nRequest: \(request)",
            schema: GenerationSchema(root: root, dependencies: []),
            options: GenerationOptions(samplingMode: .greedy)
        )
        let id = try response.content.value(String.self, forProperty: "automation")
        return candidates.first { $0.id == id }
    }

    // MARK: fill

    /// One line per param: `- name (type): description [default: value]`.
    static func paramList(_ automation: Automation) -> String {
        automation.params.map { param in
            "- \(param.name) (\(param.type))"
                + (param.description.map { ": \($0)" } ?? "")
                + (param.defaultValue.map { " [default: \($0)]" } ?? "")
        }.joined(separator: "\n")
    }

    /// Every property optional, so the model can leave out what the request doesn't say; enums limited to their
    /// options and ranges given as guides, so what comes back mostly fits.
    static func fillSchema(_ automation: Automation) -> DynamicGenerationSchema {
        DynamicGenerationSchema(name: "Parameters", properties: automation.params.map { param in
            .init(name: param.name, description: param.description, schema: schema(for: param), isOptional: true)
        })
    }

    private static func schema(for param: Param) -> DynamicGenerationSchema {
        switch param.type {
        case .string, .path: DynamicGenerationSchema(type: String.self)
        case .bool: DynamicGenerationSchema(type: Bool.self)
        case let .int(range): DynamicGenerationSchema(type: Int.self, guides: range.map { [.range($0)] } ?? [])
        case let .number(range): DynamicGenerationSchema(type: Double.self, guides: range.map { [.range($0)] } ?? [])
        case let .enum(options): DynamicGenerationSchema(name: "\(param.name)_options", anyOf: options)
        }
    }

    private func fill(_ request: String, for automation: Automation) async throws -> [String: String] {
        let session = LanguageModelSession(model: model, instructions: """
        Extract parameter values for the automation "\(automation.name)" (\(automation.description ?? "")) \
        from the user's request.
        Only include a parameter if the request states or clearly implies its value. \
        Leave out parameters the request does not mention; defaults are applied automatically.
        Keep paths exactly as the user wrote them.
        """)
        let response = try await session.respond(
            to: "Parameters:\n\(Self.paramList(automation))\n\nRequest: \(request)",
            schema: GenerationSchema(root: Self.fillSchema(automation), dependencies: []),
            options: GenerationOptions(samplingMode: .greedy)
        )
        return Self.values(in: response.content)
    }

    /// The generated properties as the strings a param takes; nulls are left out, whole numbers lose their ".0".
    static func values(in content: GeneratedContent) -> [String: String] {
        guard case let .structure(properties, _) = content.kind else { return [:] }
        return properties.compactMapValues { value in
            switch value.kind {
            case .null: nil
            case let .string(text): text
            case let .bool(flag): String(flag)
            case let .number(number):
                number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
            default: value.jsonString
            }
        }
    }
}
