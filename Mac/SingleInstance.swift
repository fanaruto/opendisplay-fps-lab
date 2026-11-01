import AppKit
import Darwin

/// Sender variants share one receiver connection. Refuse a second sender
/// before discovery starts so launching another copy cannot steal its socket.
@MainActor
enum SenderInstanceGuard {
    static func enforce() {
        let current = NSRunningApplication.current
        let ids: Set<String> = ["com.peetzweg.opensidecar.mac", "com.peetzweg.opensidecar.mac.debug", "com.peetzweg.opensidecar.mac.fps-experiment"]
        if let existing = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier != current.processIdentifier && !$0.isTerminated
                && ids.contains($0.bundleIdentifier ?? "")
                && ($0.launchDate ?? .distantPast) <= (current.launchDate ?? .distantFuture)
        }) {
            existing.activate(options: [])
            exit(0)
        }
    }
}
