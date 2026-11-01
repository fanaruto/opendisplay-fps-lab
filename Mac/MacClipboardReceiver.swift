import AppKit

/// Kept separate from the transport so validation and retry handling can be
/// exercised against a named pasteboard without replacing the user's clipboard.
@MainActor
final class MacClipboardReceiver {
    private let pasteboard: NSPasteboard
    private var receivedIDs: [String: [UUID]] = [:]
    private let rememberedTransfersPerPeer = 64

    init(pasteboard: NSPasteboard? = nil) {
        self.pasteboard = pasteboard ?? .general
    }

    /// Returns false for a retry we already applied. In particular, a retry
    /// must not overwrite something the user copied on the Mac in the meantime.
    @discardableResult
    func receive(_ transfer: ClipboardTransfer, from peer: String) throws -> Bool {
        guard !peer.isEmpty else { throw ClipboardTransferError.missingPeer }
        try ClipboardTransferCodec.validate(transfer)
        guard !(receivedIDs[peer] ?? []).contains(transfer.id) else { return false }

        let item = NSPasteboardItem()
        guard item.setString(transfer.text, forType: .string) else {
            throw ClipboardTransferError.pasteboardWriteFailed
        }
        if transfer.format == .url,
           !item.setString(transfer.text, forType: .URL) {
            throw ClipboardTransferError.pasteboardWriteFailed
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ClipboardTransferError.pasteboardWriteFailed
        }
        var ids = receivedIDs[peer] ?? []
        ids.append(transfer.id)
        receivedIDs[peer] = Array(ids.suffix(rememberedTransfersPerPeer))
        return true
    }

    func endSession(for peer: String) {
        receivedIDs.removeValue(forKey: peer)
    }
}
