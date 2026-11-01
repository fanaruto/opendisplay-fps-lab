import AppKit
import XCTest

final class ClipboardHTTPTests: XCTestCase {
    private let key = "test-key-not-a-real-credential"

    private func request(_ text: String, contentType: String = "text/plain; charset=utf-8",
                         path: String? = nil, extraHeaders: String = "") -> Data {
        let body = Data(text.utf8)
        let header = "POST \(path ?? "/\(key)/clipboard") HTTP/1.1\r\nHost: localhost\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\n\(extraHeaders)\r\n"
        return Data(header.utf8) + body
    }

    func testFragmentedUnicodeRequestIsAppliedOnlyAfterTheFullBody() throws {
        let data = request("中文 👩🏽‍💻\n第二行\t\\\"")
        for length in 0..<data.count {
            XCTAssertNil(try ClipboardHTTPRequest.parse(data.prefix(length), key: key))
        }
        guard case .copy(let transfer) = try XCTUnwrap(ClipboardHTTPRequest.parse(data, key: key)).action else {
            return XCTFail("Expected clipboard content")
        }
        XCTAssertEqual(transfer.text, "中文 👩🏽‍💻\n第二行\t\\\"")
        XCTAssertEqual(transfer.format, .text)
    }

    func testShortcutJSONAndPlainURLAreAccepted() throws {
        let url = "https://example.com/?q=ipad&n=2"
        for data in [request(url), request("{\"text\":\"\(url)\"}", contentType: "application/json")] {
            guard case .copy(let transfer) = try XCTUnwrap(ClipboardHTTPRequest.parse(data, key: key)).action else {
                return XCTFail("Expected clipboard content")
            }
            XCTAssertEqual(transfer.text, url)
            XCTAssertEqual(transfer.format, .url)
        }
    }

    func testUnauthorizedMalformedAndOversizedRequestsAreRejected() {
        let samples: [(Data, Int)] = [
            (request("private", path: "/wrong-key/clipboard"), 401),
            (request("", contentType: "text/plain"), 400),
            (request("not json", contentType: "application/json"), 400),
            (request("{\"text\":false}", contentType: "application/json"), 400),
            (request("data", contentType: "image/png"), 415),
            (request("text", extraHeaders: "Content-Length: 4\r\n"), 400),
            (request("text", extraHeaders: "Transfer-Encoding: chunked\r\n"), 400),
            (request("text", extraHeaders: "Origin: https://example.com\r\n"), 403),
            (request("text") + Data("unexpected second request".utf8), 400),
            (request(String(repeating: "字", count: 100_000)), 413),
            (Data(repeating: 65, count: ClipboardHTTPRequest.maximumHeaderBytes + 1), 431),
            (Data("POST /\(key)/clipboard HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8), 413),
        ]
        for (data, status) in samples {
            XCTAssertThrowsError(try ClipboardHTTPRequest.parse(data, key: key)) { error in
                XCTAssertEqual((error as? ClipboardHTTPRequest.Failure)?.status, status)
            }
        }
    }

    func testSetupAndShortcutDownloadsAlsoRequirePairing() throws {
        for route in ["setup", "shortcut"] {
            let data = Data("GET /\(key)/\(route) HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
            XCTAssertNotNil(try ClipboardHTTPRequest.parse(data, key: key))
            let wrong = Data("GET /wrong-key/\(route) HTTP/1.1\r\n\r\n".utf8)
            XCTAssertThrowsError(try ClipboardHTTPRequest.parse(wrong, key: key))
        }
    }

    func testRealHTTPRequestsWriteOnlyTheNamedPasteboardAndServeSetup() async throws {
        let ready = expectation(description: "Listener ready")
        let boardName = "OpenDisplayClipboardHTTPTests-\(UUID().uuidString)"
        let key = self.key
        let shortcut = Data("signed-template-fixture".utf8)
        let bridge = await MainActor.run {
            let board = NSPasteboard(name: NSPasteboard.Name(boardName))
            let bridge = MacClipboardBridge(key: key, receiver: MacClipboardReceiver(pasteboard: board),
                                            port: 0, defaults: nil, shortcutData: shortcut)
            bridge.onReady = { ready.fulfill() }
            bridge.setEnabled(true)
            return bridge
        }
        addTeardownBlock {
            await MainActor.run {
                bridge.setEnabled(false)
                NSPasteboard(name: NSPasteboard.Name(boardName)).releaseGlobally()
            }
        }
        await fulfillment(of: [ready], timeout: 5)
        let port = try await MainActor.run { try XCTUnwrap(bridge.port) }
        let base = "http://127.0.0.1:\(port)"
        func send(_ path: String, text: String? = nil) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: try XCTUnwrap(URL(string: base + path)))
            request.timeoutInterval = 3
            if let text {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, try XCTUnwrap(response as? HTTPURLResponse))
        }

        let text = "来自 iPad 👋\n链接和文字都保留"
        let (_, textResponse) = try await send("/\(key)/clipboard", text: text)
        XCTAssertEqual(textResponse.statusCode, 200)
        await MainActor.run {
            XCTAssertEqual(NSPasteboard(name: NSPasteboard.Name(boardName)).string(forType: .string), text)
        }
        let url = "https://example.com/?q=iPad&n=2"
        let (_, urlResponse) = try await send("/\(key)/clipboard", text: url)
        XCTAssertEqual(urlResponse.statusCode, 200)
        let (_, rejectedResponse) = try await send("/wrong-key/clipboard", text: "must not replace clipboard")
        XCTAssertEqual(rejectedResponse.statusCode, 401)
        let (page, setupResponse) = try await send("/\(key)/setup")
        XCTAssertEqual(setupResponse.statusCode, 200)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("复制配对地址"))
        let (download, downloadResponse) = try await send("/\(key)/shortcut")
        XCTAssertEqual(downloadResponse.statusCode, 200)
        XCTAssertEqual(download, shortcut)
        XCTAssertTrue(downloadResponse.value(forHTTPHeaderField: "Content-Disposition")?.contains("attachment") == true)
        await MainActor.run {
            let board = NSPasteboard(name: NSPasteboard.Name(boardName))
            XCTAssertEqual(board.string(forType: .string), url)
            XCTAssertEqual(board.string(forType: .URL), url)
            XCTAssertEqual(bridge.receivedCount, 2)
            bridge.setEnabled(false)
            XCTAssertNil(bridge.port)
            XCTAssertEqual(bridge.status, "已关闭")
        }
    }
}
