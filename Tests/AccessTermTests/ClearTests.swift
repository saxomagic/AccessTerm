import XCTest
@testable import AccessTerm

/// Command-K and Option-Command-K: what each takes out of the transcript, and that what
/// follows reads on from where the clear left off.
final class ClearTests: XCTestCase {
    private func feed(_ session: TerminalSession, _ text: String) {
        session.dataReceived(slice: Array(text.utf8)[...])
        session.publishUpdate()
    }

    /// OSC 133 markers, as the shell integration prints them.
    private func marker(_ kind: String) -> String { "\u{1b}]133;\(kind)\u{07}" }

    func testClearEverythingLeavesTheLineBeingTypedOn() {
        let session = TerminalSession(cols: 80, rows: 5)
        feed(session, "one\r\ntwo\r\nthree\r\n$ ")
        XCTAssertEqual(session.transcript.lines, ["one", "two", "three"])

        let removed = session.clear(.everything)
        XCTAssertEqual(removed, 3)
        XCTAssertEqual(session.transcript.lines, [])
        XCTAssertEqual(session.transcript.length, 0)

        // The prompt that was being typed at is read on as usual.
        feed(session, "ls\r\nfile\r\n$ ")
        XCTAssertEqual(session.transcript.lines, ["$ ls", "file"])
        XCTAssertEqual(session.transcript.offset(ofLine: 1), "$ ls\n".count)
    }

    func testClearScrollbackKeepsWhatIsOnTheScreen() {
        let session = TerminalSession(cols: 80, rows: 5)
        feed(session, (1...10).map { "l\($0)\r\n" }.joined() + "$ ")
        XCTAssertEqual(session.transcript.lines.count, 10)

        // Five rows on the screen: the prompt and the four lines above it.
        let removed = session.clear(.scrollback)
        XCTAssertEqual(removed, 6)
        XCTAssertEqual(session.transcript.lines, ["l7", "l8", "l9", "l10"])
        XCTAssertEqual(session.transcript.length, "l7\nl8\nl9\nl10\n".count)

        feed(session, "more\r\n$ ")
        XCTAssertEqual(session.transcript.lines.last, "$ more")
        XCTAssertEqual(session.transcript.lines.count, 5)
    }

    func testClearScrollbackWithNothingScrolledOffTakesNothing() {
        let session = TerminalSession(cols: 80, rows: 10)
        session.appendExternal(["AccessTerm ready."])
        feed(session, "one\r\ntwo\r\n$ ")
        XCTAssertEqual(session.clear(.scrollback), 0)
        XCTAssertEqual(session.transcript.lines, ["AccessTerm ready.", "one", "two"])
    }

    func testClearScrollbackTakesWhatAScreenWipeLeftBehind() {
        let session = TerminalSession(cols: 80, rows: 10)
        feed(session, "one\r\ntwo\r\n$ clear\r\n\u{1b}[H\u{1b}[2J$ ")
        let before = session.transcript.lines
        XCTAssertTrue(before.contains("one"))
        session.clear(.scrollback)
        XCTAssertEqual(session.transcript.lines, [])
    }

    func testBlocksGoWithTheirLinesAndLaterOnesAreRenumbered() {
        let session = TerminalSession(cols: 80, rows: 5)
        func run(_ command: String, output: String) -> String {
            marker("A") + "$ " + marker("B") + command + "\r\n" + marker("C") + output + "\r\n" + marker("D;0")
        }
        feed(session, run("a", output: "A-out") + run("b", output: "B-out") + marker("A") + "$ " + marker("B"))
        XCTAssertEqual(session.commandBlocks.map(\.command), ["a", "b"])

        session.clear(.everything)
        XCTAssertEqual(session.commandBlocks.map(\.command), [])

        feed(session, "c\r\n" + marker("C") + "C-out\r\n" + marker("D;0") + marker("A") + "$ " + marker("B"))
        XCTAssertEqual(session.commandBlocks.map(\.command), ["c"])
        let block = session.commandBlocks[0]
        XCTAssertEqual(session.transcript.lines[block.commandLine], "$ c")
        XCTAssertEqual(session.transcript.lines[block.outputLines.lowerBound], "C-out")
    }

    func testClearingWhileACommandRunsLetsItFinish() {
        let session = TerminalSession(cols: 80, rows: 5)
        feed(session, marker("A") + "$ " + marker("B") + "sleep\r\n" + marker("C") + "early\r\n")
        XCTAssertTrue(session.programIsRunning)

        session.clear(.everything)
        XCTAssertTrue(session.programIsRunning, "the command is still running")
        XCTAssertEqual(session.commandBlocks.count, 0, "its lines are gone, so there is nothing to step to")

        feed(session, "late\r\n" + marker("D;3"))
        XCTAssertFalse(session.programIsRunning)
        XCTAssertEqual(session.transcript.lines.last, "late")
    }
}
