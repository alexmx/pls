import Foundation
@testable import PlsCore
import Testing

func makeEntry(
    _ id: String,
    params: [String: String] = [:],
    chosen: [String] = [],
    via: HistoryEntry.Trigger = .run,
    exit: Int32 = 0,
    at: Date = Date(timeIntervalSince1970: 1_800_000_000)
) -> HistoryEntry {
    HistoryEntry(at: at, id: id, params: params, chosen: chosen, via: via, exit: exit, seconds: 0.123)
}

@Suite(.timeLimit(.minutes(1)))
struct HistoryTests {
    @Test func appendsAndReadsBackNewestFirst() throws {
        let home = try TempHome()
        let store = HistoryStore(file: home.url.appending(path: "state/nested/history.jsonl"))
        try store.append(makeEntry("a", params: ["port": "3000"], chosen: ["port"]))
        try store.append(makeEntry("b", exit: 3))
        try store.append(makeEntry("c", via: .again))

        #expect(store.recent(10).map(\.id) == ["c", "b", "a"])
        #expect(store.recent(2).map(\.id) == ["c", "b"])
        #expect(store.recent(10).last == makeEntry("a", params: ["port": "3000"], chosen: ["port"]))
    }

    @Test func storesOneReadableLinePerRun() throws {
        let home = try TempHome()
        let store = HistoryStore(file: home.url.appending(path: "history.jsonl"))
        try store.append(makeEntry("kill-port", params: ["port": "3000"], chosen: ["port"]))
        let text = try String(contentsOf: store.file, encoding: .utf8)
        #expect(text == """
        {"at":"2027-01-15T08:00:00Z","chosen":["port"],"exit":0,"id":"kill-port","params":{"port":"3000"},\
        "seconds":0.12,"via":"run"}
        
        """)
    }

    @Test func skipsLinesItCantRead() throws {
        let home = try TempHome()
        let store = HistoryStore(file: home.url.appending(path: "history.jsonl"))
        try store.append(makeEntry("a"))
        let handle = try FileHandle(forWritingTo: store.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n{\"id\":\"half\"}\n".utf8))
        try handle.close()
        try store.append(makeEntry("b"))

        #expect(store.recent(10).map(\.id) == ["b", "a"])
    }

    @Test func missingFileIsEmptyHistory() {
        #expect(HistoryStore(file: URL(filePath: "/nonexistent/history.jsonl")).recent(5).isEmpty)
    }

    @Test func unwritableFileIsAnError() throws {
        let home = try TempHome()
        let file = home.url.appending(path: "history.jsonl")
        try Data().write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)
        #expect(throws: HistoryStore.WriteError.self) { try HistoryStore(file: file).append(makeEntry("a")) }
    }

    @Test func locationFollowsPlsHomeThenXDGStateHome() {
        #expect(HistoryStore.defaultFile(environment: ["PLS_HOME": "/tmp/p", "XDG_STATE_HOME": "/tmp/s"]).path
            == "/tmp/p/history.jsonl")
        #expect(HistoryStore.defaultFile(environment: ["XDG_STATE_HOME": "/tmp/s"]).path
            == "/tmp/s/pls/history.jsonl")
        #expect(HistoryStore.defaultFile(environment: [:]).path.hasSuffix("/.local/state/pls/history.jsonl"))
    }
}
