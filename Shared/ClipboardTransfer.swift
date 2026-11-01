import Foundation

/// A small, additive control message. Large media needs a separate transfer
/// mechanism; never raise the control channel's existing one-MiB frame limit.
struct ClipboardTransfer: Codable, Equatable {
    enum Format: String, Codable {
        case text
        case url
    }

    let type: String
    let id: UUID
    let format: Format
    let text: String

    init(text: String, format: Format = .text, id: UUID = UUID()) {
        self.type = ClipboardTransferCodec.messageType
        self.id = id
        self.format = format
        self.text = text
    }
}

enum ClipboardTransferError: Error, Equatable {
    case wrongMessageType
    case emptyContent
    case textTooLarge
    case frameTooLarge
    case invalidURL
    case missingPeer
    case pasteboardWriteFailed
}

enum ClipboardTransferCodec {
    static let messageType = "clipboard"
    static let maximumTextBytes = 256 * 1024
    // receiveControl accepts lengths strictly less than one MiB.
    static let maximumFrameBytes = (1 << 20) - 1

    static func validate(_ transfer: ClipboardTransfer) throws {
        guard transfer.type == messageType else {
            throw ClipboardTransferError.wrongMessageType
        }
        guard !transfer.text.isEmpty else { throw ClipboardTransferError.emptyContent }
        guard transfer.text.utf8.count <= maximumTextBytes else {
            throw ClipboardTransferError.textTooLarge
        }
        if transfer.format == .url {
            guard let url = URL(string: transfer.text), url.scheme != nil else {
                throw ClipboardTransferError.invalidURL
            }
        }
    }

    static func encode(_ transfer: ClipboardTransfer) throws -> Data {
        try validate(transfer)
        let data = try JSONEncoder().encode(transfer)
        guard data.count <= maximumFrameBytes else {
            throw ClipboardTransferError.frameTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> ClipboardTransfer {
        guard data.count <= maximumFrameBytes else {
            throw ClipboardTransferError.frameTooLarge
        }
        let transfer = try JSONDecoder().decode(ClipboardTransfer.self, from: data)
        try validate(transfer)
        return transfer
    }
}
