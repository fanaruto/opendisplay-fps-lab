import Foundation

/// One bounded HTTP/1 request per connection. Pairing keys and clipboard contents
/// must never be included in diagnostic output or error responses.
struct ClipboardHTTPRequest {
    static let maximumHeaderBytes = 8 * 1024
    static let maximumBodyBytes = ClipboardTransferCodec.maximumFrameBytes

    struct Failure: Error {
        let status: Int
        let message: String
    }

    enum Action {
        case copy(ClipboardTransfer)
        case setup
        case shortcut
    }

    let action: Action

    static func parse(_ data: Data, key: String) throws -> ClipboardHTTPRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            guard data.count <= maximumHeaderBytes else { throw failure(431, "Headers too large") }
            return nil
        }
        guard separator.lowerBound <= maximumHeaderBytes,
              let header = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
            throw failure(400, "Invalid headers")
        }
        let lines = header.components(separatedBy: "\r\n")
        let request = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[2] == "HTTP/1.1" || request[2] == "HTTP/1.0" else {
            throw failure(400, "Invalid request")
        }
        let path = request[1].split(separator: "/", omittingEmptySubsequences: false)
        guard !key.isEmpty, path.count == 3, path[0].isEmpty,
              constantTimeEqual(String(path[1]), key),
              ["clipboard", "setup", "shortcut"].contains(String(path[2])) else {
            throw failure(401, "Pairing required")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                  !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                throw failure(400, "Invalid header")
            }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { throw failure(400, "Duplicate header") }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["transfer-encoding"] == nil else {
            throw failure(400, "Transfer encoding is unsupported")
        }
        // Shortcuts sends native URL requests without a browser Origin header.
        guard headers["origin"] == nil else { throw failure(403, "Native clients only") }
        if request[0] == "GET", path[2] != "clipboard" {
            guard data.count == separator.upperBound,
                  headers["content-length"] == nil || headers["content-length"] == "0" else {
                throw failure(400, "GET body is unsupported")
            }
            return ClipboardHTTPRequest(action: path[2] == "setup" ? .setup : .shortcut)
        }
        guard request[0] == "POST", path[2] == "clipboard" else {
            throw failure(405, "Use the pairing page or POST clipboard content")
        }
        guard let lengthText = headers["content-length"], !lengthText.isEmpty,
              lengthText.utf8.allSatisfy({ (48...57).contains($0) }),
              let length = Int(lengthText), length <= maximumBodyBytes else {
            throw failure(413, "Invalid or oversized body")
        }
        let bodyBytes = data.count - separator.upperBound
        guard bodyBytes <= length else { throw failure(400, "One request per connection") }
        guard bodyBytes == length else { return nil }
        let body = Data(data[separator.upperBound...])
        let contentType = (headers["content-type"] ?? "").split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased()
        let transfer: ClipboardTransfer
        do {
            switch contentType {
            case "application/json":
                let object = try JSONSerialization.jsonObject(with: body)
                guard let json = object as? [String: Any] else { throw failure(400, "Expected JSON object") }
                if json["type"] != nil {
                    transfer = try ClipboardTransferCodec.decode(body)
                } else {
                    guard let text = json["text"] as? String else { throw failure(400, "Expected text") }
                    transfer = textTransfer(text)
                }
            case "text/plain":
                guard let text = String(data: body, encoding: .utf8) else {
                    throw failure(400, "Expected UTF-8 text")
                }
                transfer = textTransfer(text)
            default:
                throw failure(415, "Use JSON or UTF-8 plain text")
            }
            try ClipboardTransferCodec.validate(transfer)
        } catch let error as Failure {
            throw error
        } catch ClipboardTransferError.textTooLarge {
            throw failure(413, "Text exceeds 256 KiB")
        } catch {
            throw failure(400, "Invalid clipboard content")
        }
        return ClipboardHTTPRequest(action: .copy(transfer))
    }

    private static func textTransfer(_ text: String) -> ClipboardTransfer {
        let isURL = !text.contains(where: \.isWhitespace) && URL(string: text)?.scheme != nil
        return ClipboardTransfer(text: text, format: isURL ? .url : .text)
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func failure(_ status: Int, _ message: String) -> Failure {
        Failure(status: status, message: message)
    }

    static func response(status: Int, message: String) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: ["ok": status == 200, "message": message])) ?? Data()
        return contentResponse(status: status, type: "application/json; charset=utf-8", body: body)
    }

    static func contentResponse(status: Int = 200, type: String, body: Data,
                                attachment: Bool = false) -> Data {
        let filename = "发送剪贴板到 Mac.shortcut".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let disposition = attachment ? "Content-Disposition: attachment; filename=SendClipboardToMac.shortcut; filename*=UTF-8''\(filename)\r\n" : ""
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(type)\r\n\(disposition)Content-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\n\r\n"
        return Data(header.utf8) + body
    }
}
