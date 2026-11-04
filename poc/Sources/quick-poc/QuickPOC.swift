import Foundation
import FoundationModels

@main
struct QuickPOC {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        var model = ModelChoice.local
        if let i = args.firstIndex(of: "--model"), i + 1 < args.count {
            model = ModelChoice(rawValue: args[i + 1]) ?? .local
            args.removeSubrange(i...(i + 1))
        }
        var only: String?
        if let i = args.firstIndex(of: "--only"), i + 1 < args.count {
            only = args[i + 1]
            args.removeSubrange(i...(i + 1))
        }
        let command = args.first ?? "help"
        let text = args.dropFirst().joined(separator: " ")

        do {
            switch command {
            case "status": try await status()
            case "pick": try await pick(text, model: model)
            case "oneoff": try await oneOff(text, model: model)
            case "create": try await create(text, model: model)
            case "eval": try await Eval(model: model).run(only: only)
            default: print(usage)
            }
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }

    static let usage = """
        quick-poc status                       model availability + catalog prompt size
        quick-poc pick "<request>"             route to a saved automation and fill its params
        quick-poc oneoff "<task>"              generate a one-off zsh command (not executed)
        quick-poc create "<description>"       draft a new automation (not saved)
        quick-poc eval [--only pick|oneoff|create]
        Options: --model local|pcc             on-device (default) or Private Cloud Compute
        """

    static func status() async throws {
        let local = SystemLanguageModel.default
        print("on-device model: \(local.availability)")
        if local.isAvailable {
            print("  context size: \(local.contextSize) tokens")
            let catalog = try Catalog.load()
            let tokens = try await local.tokenCount(for: catalog.routingListing)
            print("  routing listing: \(catalog.automations.count) automations ≈ \(tokens) tokens")
        }
        let pcc = PrivateCloudComputeLanguageModel()
        print("private cloud compute: \(pcc.availability)")
    }

    static func pick(_ query: String, model: ModelChoice) async throws {
        let catalog = try Catalog.load()
        let r = try await Picker(catalog: catalog, model: model).pick(query)
        print(String(format: "route %.2fs · fill %.2fs", r.routeSeconds, r.fillSeconds))
        guard let a = catalog.automation(r.id) else { return print("→ no matching automation") }
        let shown = a.allParams.map { p in "\(p.name)=\(r.params[p.name] ?? "\(p.default ?? "?") (default)")" }
        print("→ \(a.name) [\(a.id)]  \(shown.joined(separator: ", "))")
        print("  would run: \(a.render(r.params))")
    }

    static func oneOff(_ task: String, model: ModelChoice) async throws {
        let (plan, secs) = try await timed { try await generateOneOff(task, model: model) }
        let c = check(script: plan.command, kind: "shell")
        print(String(format: "%.2fs", secs))
        print("$ \(plan.command)")
        print("  \(plan.explanation)\(plan.destructive ? "  ⚠️ destructive" : "")")
        print("  check: \(describe(c))")
    }

    static func create(_ request: String, model: ModelChoice) async throws {
        let (d, secs) = try await timed { try await generateAutomation(request, model: model) }
        let c = check(script: d.script, kind: d.kind)
        print(String(format: "%.2fs", secs))
        print("\(d.name) [\(d.id)] · \(d.kind) — \(d.description)")
        for p in d.params { print("  param \(p.name): \(p.type) — \(p.description)\(p.defaultValue.isEmpty ? "" : " [default: \(p.defaultValue)]")") }
        print("---\n\(d.script)\n---")
        print("check: \(describe(c))")
    }
}

func describe(_ c: CheckResult) -> String {
    var parts: [String] = [c.syntaxOK ? "syntax ok" : "SYNTAX ERROR: \(c.syntaxError)"]
    if !c.missingTools.isEmpty { parts.append("missing tools: \(c.missingTools.joined(separator: ", "))") }
    return parts.joined(separator: " · ")
}
