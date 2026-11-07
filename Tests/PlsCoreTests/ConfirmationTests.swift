@testable import PlsCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ConfirmationTests {
    private func binding(action: String?) throws -> Binding {
        let automation = try makeAutomation(params: "action: enum(shutdown|restart|cancel)")
        var binding = Binding(defaultsOf: automation)
        if let action, let param = automation.params.first {
            try binding.supply(action, for: param, source: .given)
        }
        return binding
    }

    @Test func asksOnlyForTheListedChoices() throws {
        let confirm = Confirmation.when(param: "action", choices: ["shutdown", "restart"])
        #expect(try confirm.asks(for: binding(action: "restart")))
        #expect(try !confirm.asks(for: binding(action: "cancel")))
        // Not known yet: prompting fills it in, and pls decides again then.
        #expect(try !confirm.asks(for: binding(action: nil)))
    }

    @Test func alwaysAndNeverIgnoreTheValues() throws {
        #expect(try Confirmation.always.asks(for: binding(action: "cancel")))
        #expect(try !Confirmation.never.asks(for: binding(action: "shutdown")))
    }
}
