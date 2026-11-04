import QuickCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SmokeTests {
    @Test func versionIsSet() {
        #expect(!Quick.version.isEmpty)
    }
}
