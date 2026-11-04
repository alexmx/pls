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

    @Test func invalidUTF8OnOneLineSkipsOnlyThatLine() throws {
        let home = try TempHome()
        let store = HistoryStore(file: home.url.appending(path: "history.jsonl"))
        try store.append(makeEntry("a"))
        try appendRaw(Data([0xFF, 0xFE]) + Data(" junk\n".utf8), to: store.file)
        try store.append(makeEntry("b"))
        #expect(store.recent(10).map(\.id) == ["b", "a"])
    }

    /// JSONEncoder leaves U+2028/U+2029/U+0085 unescaped; they must not split a line.
    @Test func unicodeLineSeparatorsInValuesSurvive() throws {
        let home = try TempHome()
        let store = HistoryStore(file: home.url.appending(path: "history.jsonl"))
        let entry = makeEntry("echo", params: ["msg": "a\u{2028}b\u{2029}c\u{85}d"], chosen: ["msg"])
        try store.append(makeEntry("before"))
        try store.append(entry)
        #expect(store.recent(1) == [entry])
    }

    /// A line cut off by a failed write must not swallow the next entry.
    @Test func appendAfterATruncatedLineStartsAFreshLine() throws {
        let home = try TempHome()
        let store = HistoryStore(file: home.url.appending(path: "history.jsonl"))
        try store.append(makeEntry("a"))
        try appendRaw(Data(#"{"id":"cut off"#.utf8), to: store.file)
        try store.append(makeEntry("b"))
        #expect(store.recent(10).map(\.id) == ["b", "a"])
    }

    private func appendRaw(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
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

    @Test func entryFromABindingMarksChosenValues() throws {
        let automation = try makeAutomation(
            "compress", params: "folder: path = ~/Desktop", "quality: int = 80", "note: string?"
        )
        var binding = try ParamBinder.bind(automation, arguments: ["--quality", "60"])
        try binding.supply("hi", for: automation.params[2], source: .prompted)
        let at = Date(timeIntervalSince1970: 0)

        let entry = HistoryEntry(binding, via: .run, exit: 2, seconds: 1.5, at: at)

        #expect(entry == HistoryEntry(
            at: at, id: "compress", params: ["folder": "~/Desktop", "quality": "60", "note": "hi"],
            chosen: ["note", "quality"], via: .run, exit: 2, seconds: 1.5
        ))
    }

    @Test func chosenValuesLeaveOutDefaults() {
        let entry = makeEntry("a", params: ["folder": "~/Desktop", "quality": "60"], chosen: ["quality"])
        #expect(entry.chosenValues == ["quality": "60"])
    }

    @Test func locationFollowsPlsHomeThenXDGStateHome() {
        #expect(HistoryStore.defaultFile(environment: ["PLS_HOME": "/tmp/p", "XDG_STATE_HOME": "/tmp/s"]).path
            == "/tmp/p/history.jsonl")
        #expect(HistoryStore.defaultFile(environment: ["XDG_STATE_HOME": "/tmp/s"]).path
            == "/tmp/s/pls/history.jsonl")
        #expect(HistoryStore.defaultFile(environment: [:]).path.hasSuffix("/.local/state/pls/history.jsonl"))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ReplayTests {
    @Test func replaysChosenValuesAndRecomputesDefaults() throws {
        let automation = try makeAutomation(
            "compress", params: "folder: path = ~/Desktop", "quality: int(1...100) = 80"
        )
        // Last run used folder=~/Old as a default; the default has since changed to ~/Desktop.
        let entry = makeEntry("compress", params: ["folder": "~/Old", "quality": "60"], chosen: ["quality"])

        let binding = try ParamBinder.replay(entry.chosenValues, for: automation)

        #expect(binding.values == [
            "folder": BoundValue("~/Desktop", .defaultValue),
            "quality": BoundValue("60", .repeated)
        ])
    }

    @Test func dropsParamsTheAutomationNoLongerHas() throws {
        let automation = try makeAutomation("a", params: "kept: string")
        let entry = makeEntry("a", params: ["kept": "x", "gone": "y"], chosen: ["gone", "kept"])
        #expect(try ParamBinder.replay(entry.chosenValues, for: automation).values == ["kept": BoundValue(
            "x",
            .repeated
        )])
    }

    @Test func leavesNewRequiredParamsMissing() throws {
        let automation = try makeAutomation("a", params: "old: string", "new: int")
        let binding = try ParamBinder.replay(["old": "x"], for: automation)
        #expect(binding.missing.map(\.name) == ["new"])
    }

    @Test func storedValueThatNoLongerFitsIsAnError() throws {
        let automation = try makeAutomation("a", params: "quality: int(1...50)")
        let entry = makeEntry("a", params: ["quality": "80"], chosen: ["quality"])
        #expect(throws: BindingError("quality: 80 is outside 1...50")) {
            try ParamBinder.replay(entry.chosenValues, for: automation)
        }
    }

    @Test func repeatedValuesStayChosenInTheNextEntry() throws {
        let automation = try makeAutomation("a", params: "port: int")
        let binding = try ParamBinder.replay(["port": "1"], for: automation)
        let next = HistoryEntry(binding, via: .again, exit: 0, seconds: 0, at: Date())
        #expect(next.chosen == ["port"])
    }
}
