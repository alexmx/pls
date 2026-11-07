import Foundation
import FoundationModels

/// Natural language → a binding, with Apple's on-device model. Two stages: route the request to one
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
        try requireModel()
        let candidates = Self.candidates(in: library)
        guard !candidates.isEmpty else { return nil }
        return try await asking(about: candidates) {
            guard let automation = try await route(request, shortlisting: candidates) else { return nil }
            let values = automation.params.isEmpty ? [:] : try await fill(request, for: automation)
            return ParamBinder.bind(automation, request: request, values: values)
        }
    }

    /// The automation `request` routes to, or nil if none fits: routing alone, without filling values.
    public func route(_ request: String, in library: Library) async throws(ModelError) -> Automation? {
        try requireModel()
        let candidates = Self.candidates(in: library)
        guard !candidates.isEmpty else { return nil }
        return try await asking(about: candidates) {
            try await route(request, shortlisting: candidates)
        }
    }

    /// Runs `body`, which asks the model about `candidates`, turning its errors into `.failed` with a reason.
    private func asking<T>(
        about candidates: [Automation], _ body: () async throws -> T
    ) async throws(ModelError) -> T {
        do {
            return try await body()
        } catch where Self.isContextOverflow(error) {
            throw .failed("""
            the request and the \(candidates.count) automations offered don't fit in the model's context; \
            run `pls doctor`, and describe fewer automations
            """)
        } catch {
            throw .failed("the model couldn't answer: \(error.localizedDescription)")
        }
    }

    /// Throws `.unavailable` with the reason when the model can't be used.
    private func requireModel() throws(ModelError) {
        if let reason = Self.unavailableReason(model.availability, environment: environment) {
            throw .unavailable(reason)
        }
    }

    /// Whether `error` says the input didn't fit in the context. macOS 27 throws `LanguageModelError`; macOS 26 the
    /// `GenerationError` case it deprecates.
    private static func isContextOverflow(_ error: any Error) -> Bool {
        if #available(macOS 27, *), case LanguageModelError.contextSizeExceeded = error {
            return true
        }
        if case LanguageModelSession.GenerationError.exceededContextWindowSize = error {
            return true
        }
        return false
    }

    /// Why the model can't be used, or nil if it can.
    public static func unavailableReason(
        _ availability: SystemLanguageModel.Availability,
        environment: [String: String] = ProcessInfo.processInfo.environment
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

    static let routingInstructions = """
    You route a user's request to one of their saved automations.
    Pick the automation whose purpose matches the request. \
    If no automation can do what the user asked, answer "\(noMatch)". Do not guess.
    """

    static func routingPrompt(_ candidates: [Automation], request: String) -> String {
        "Automations:\n\(routingList(candidates))\n\nRequest: \(request)"
    }

    /// The answer is limited to one of the ids or `noMatch`.
    static func routingSchema(_ candidates: [Automation]) throws -> GenerationSchema {
        let root = DynamicGenerationSchema(name: "Route", properties: [
            .init(
                name: "automation",
                description: "id of the automation that does what the user asked, or \(noMatch)",
                schema: DynamicGenerationSchema(name: "AutomationID", anyOf: candidates.map(\.id) + [noMatch])
            )
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Routes over the shortlist for `request`, then over the wider fallback if nothing in it fits: the shortlist ranks
    /// by meaning alone, so the right automation can fall just outside it. Both come from one ranking.
    private func route(_ request: String, shortlisting candidates: [Automation]) async throws -> Automation? {
        guard candidates.count > Shortlist.threshold, let ranking = Shortlist.ranking(for: request, among: candidates)
        else { return try await route(request, among: candidates) }
        if let picked = try await route(request, among: ranking.closest(Shortlist.size)) {
            return picked
        }
        return try await route(request, among: ranking.closest(Shortlist.fallbackSize))
    }

    private func route(_ request: String, among candidates: [Automation]) async throws -> Automation? {
        let session = LanguageModelSession(model: model, instructions: Self.routingInstructions)
        let response = try await session.respond(
            to: Self.routingPrompt(candidates, request: request),
            schema: Self.routingSchema(candidates),
            options: GenerationOptions(samplingMode: .greedy)
        )
        let id = try response.content.value(String.self, forProperty: "automation")
        return candidates.first { $0.id == id }
    }

    // MARK: context budget

    /// How much of the model's context routing a request over `library` takes: the instructions, the
    /// prompt listing every described automation and the schema repeating their ids, without the request itself.
    public func routingBudget(for library: Library) async throws(ModelError) -> RoutingBudget {
        try requireModel()
        guard #available(macOS 26.4, *) else { throw .failed("counting tokens needs macOS 26.4 or later") }
        let candidates = Self.candidates(in: library)
        do {
            let instructions = try await model.tokenCount(for: Instructions(Self.routingInstructions))
            let prompt = try await model.tokenCount(for: Prompt(Self.routingPrompt(candidates, request: "")))
            let schema = try await model.tokenCount(for: Self.routingSchema(candidates))
            return RoutingBudget(
                tokens: instructions + prompt + schema, contextSize: model.contextSize, automations: candidates.count
            )
        } catch {
            throw .failed("couldn't count the routing list's tokens: \(error.localizedDescription)")
        }
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

/// How much of the model's context routing takes, from `NLResolver.routingBudget(for:)`.
public struct RoutingBudget: Equatable, Sendable {
    public let tokens: Int
    public let contextSize: Int
    /// The automations offered to the model (the ones with a description).
    public let automations: Int

    /// Whether requests read a shortlist of the closest automations first (`tokens` counts them all, as the fallback
    /// to every automation reads them).
    public var isShortlisted: Bool {
        automations > Shortlist.threshold
    }

    /// What to tell the user once the routing list leaves little room for the request and the answer; nil until then.
    public var warning: String? {
        // A shortlisted request reads at most the fallback's closest automations, about their share of the tokens.
        let read = isShortlisted ? tokens * min(Shortlist.fallbackSize, automations) / automations : tokens
        return if read > contextSize {
            "the routing list is bigger than the model's context, so requests will fail; describe fewer automations"
        } else if read * 4 >= contextSize * 3 {
            "the routing list uses most of the model's context; requests may fail as the library grows"
        } else {
            nil
        }
    }
}
