import AppKit
import XCTest

final class ClipboardTransferTests: XCTestCase {
    func testUnicodeAndControlCharactersSurviveTheWire() throws {
        let transfer = ClipboardTransfer(text: "中文 👩🏽‍💻\n\"quoted\"\t\\path\u{0}")
        let data = try ClipboardTransferCodec.encode(transfer)
        XCTAssertEqual(try ClipboardTransferCodec.decode(data), transfer)
    }

    func testEscapingCannotCreateAnOversizedControlFrame() {
        let transfer = ClipboardTransfer(
            text: String(repeating: "\u{0}", count: ClipboardTransferCodec.maximumTextBytes))
        XCTAssertThrowsError(try ClipboardTransferCodec.encode(transfer)) { error in
            XCTAssertEqual(error as? ClipboardTransferError, .frameTooLarge)
        }
    }

    func testMalformedAndUnrelatedMessagesAreNotClipboardTransfers() {
        let samples = [
            #"{"type":"touch","id":"B8493D41-6ABF-4A07-97EE-C1A74D111D09","format":"text","text":"hi"}"#,
            #"{"type":"clipboard","id":"invalid","format":"text","text":"hi"}"#,
            #"{"type":"clipboard","id":"B8493D41-6ABF-4A07-97EE-C1A74D111D09","format":"image","text":"hi"}"#,
            #"{"type":"clipboard"}"#,
        ]
        for sample in samples {
            XCTAssertThrowsError(try ClipboardTransferCodec.decode(Data(sample.utf8)))
        }
    }

    func testOversizedIncomingFramesAreRejectedBeforeJSONDecoding() {
        let data = Data(repeating: 0, count: ClipboardTransferCodec.maximumFrameBytes + 1)
        XCTAssertThrowsError(try ClipboardTransferCodec.decode(data)) { error in
            XCTAssertEqual(error as? ClipboardTransferError, .frameTooLarge)
        }
    }

    func testWritesPlainTextAndTypedURLToANamedMacPasteboard() async throws {
        try await MainActor.run {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let receiver = MacClipboardReceiver(pasteboard: board)
            let text = ClipboardTransfer(text: "来自 iPad\n第二行 👋")
            XCTAssertTrue(try receiver.receive(text, from: "test-ipad"))
            XCTAssertEqual(board.string(forType: .string), text.text)

            let url = ClipboardTransfer(text: "https://example.com/?q=iPad", format: .url)
            XCTAssertTrue(try receiver.receive(url, from: "test-ipad"))
            XCTAssertEqual(board.string(forType: .string), url.text)
            XCTAssertEqual(board.string(forType: .URL), url.text)
        }
    }

    func testRetryDoesNotOverwriteANewerLocalCopy() async throws {
        try await MainActor.run {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let receiver = MacClipboardReceiver(pasteboard: board)
            let transfer = ClipboardTransfer(text: "from iPad")
            XCTAssertTrue(try receiver.receive(transfer, from: "test-ipad"))
            board.clearContents()
            board.setString("new local copy", forType: .string)
            XCTAssertFalse(try receiver.receive(transfer, from: "test-ipad"))
            XCTAssertEqual(board.string(forType: .string), "new local copy")
        }
    }

    func testRejectedContentLeavesExistingClipboardIntact() async throws {
        try await MainActor.run {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.setString("keep this", forType: .string)
            let receiver = MacClipboardReceiver(pasteboard: board)
            let samples = [
                ClipboardTransfer(text: ""),
                ClipboardTransfer(text: "not an absolute URL", format: .url),
                ClipboardTransfer(text: String(repeating: "字", count: 100_000)),
            ]
            for transfer in samples {
                XCTAssertThrowsError(try receiver.receive(transfer, from: "test-ipad"))
                XCTAssertEqual(board.string(forType: .string), "keep this")
            }
            XCTAssertThrowsError(try receiver.receive(ClipboardTransfer(text: "x"), from: ""))
            XCTAssertEqual(board.string(forType: .string), "keep this")
        }
    }
}
