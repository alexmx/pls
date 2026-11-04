import Foundation
import FoundationModels

struct PickResult {
    let id: String          // automation id or "none"
    let params: [String: String]
    let routeSeconds: Double
    let fillSeconds: Double
}

/// Two-stage pick & fill:
/// 1. route: the model may only answer with a catalog id (or "none") — enforced by the schema.
/// 2. fill: a schema built from that automation's params, so values are typed / constrained.
struct Picker {
    let catalog: Catalog
    let model: ModelChoice

    func pick(_ query: String) async throws -> PickResult {
        let (id, routeSeconds) = try await timed { try await route(query) }
        guard id != "none", let automation = catalog.automation(id), !automation.allParams.isEmpty else {
            return PickResult(id: id, params: [:], routeSeconds: routeSeconds, fillSeconds: 0)
        }
        let (params, fillSeconds) = try await timed { try await fill(query, for: automation) }
        return PickResult(id: id, params: params, routeSeconds: routeSeconds, fillSeconds: fillSeconds)
    }

    func route(_ query: String) async throws -> String {
        let ids = catalog.automations.map(\.id) + ["none"]
        let root = DynamicGenerationSchema(name: "Route", properties: [
            .init(name: "automation",
                  description: "id of the automation that does what the user asked, or none",
                  schema: DynamicGenerationSchema(name: "AutomationID", anyOf: ids))
        ])
        let session = model.session(instructions: """
            You route a user's request to one of their saved automations.
            Pick the automation whose purpose matches the request. \
            If no automation can do what the user asked, answer "none". Do not guess.
            """)
        let prompt = "Automations:\n\(catalog.routingListing)\n\nRequest: \(query)"
        let response = try await session.respond(
            to: Prompt(prompt), schema: try GenerationSchema(root: root, dependencies: []), options: deterministic)
        return try response.content.value(String.self, forProperty: "automation")
    }

    func fill(_ query: String, for a: Automation) async throws -> [String: String] {
        let root = DynamicGenerationSchema(name: "Parameters", properties: a.allParams.map { p in
            .init(name: p.name, description: p.description, schema: schema(for: p, in: a), isOptional: true)
        })
        let session = model.session(instructions: """
            Extract parameter values for the automation "\(a.name)" (\(a.description)) from the user's request.
            Only include a parameter if the request states or clearly implies its value. \
            Leave out parameters the request does not mention; defaults are applied automatically.
            Keep paths exactly as the user wrote them.
            """)
        let listing = a.allParams.map { p in
            "- \(p.name) (\(p.type.rawValue)): \(p.description)" + (p.default.map { " [default: \($0)]" } ?? "")
        }.joined(separator: "\n")
        let response = try await session.respond(
            to: Prompt("Parameters:\n\(listing)\n\nRequest: \(query)"),
            schema: try GenerationSchema(root: root, dependencies: []), options: deterministic)
        return flatten(response.content)
    }

    private func schema(for p: Param, in a: Automation) -> DynamicGenerationSchema {
        switch p.type {
        case .string, .path: DynamicGenerationSchema(type: String.self)
        case .bool: DynamicGenerationSchema(type: Bool.self)
        case .number: DynamicGenerationSchema(type: Double.self)
        case .enum: DynamicGenerationSchema(name: "\(a.id)_\(p.name)", anyOf: p.options ?? [])
        case .int:
            if let lo = p.min, let hi = p.max {
                DynamicGenerationSchema(type: Int.self, guides: [.range(lo...hi)])
            } else {
                DynamicGenerationSchema(type: Int.self)
            }
        }
    }
}
