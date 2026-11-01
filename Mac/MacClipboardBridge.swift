import AppKit
import Combine
import Network
import SystemConfiguration

@MainActor
final class MacClipboardBridge: ObservableObject {
    nonisolated static let defaultPort: UInt16 = 43187
    private static let enabledPreference = "clipboardManualReceiveEnabled"
    @Published private(set) var enabled = false
    @Published private(set) var status = "已关闭"
    @Published private(set) var port: UInt16?
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var receivedCount = 0

    private let receiver: MacClipboardReceiver
    private let defaults: UserDefaults?
    private let requestedPort: UInt16
    private let shortcutData: Data?
    private var key: String?
    private var listener: NWListener?
    private var clients: [UUID: ClipboardHTTPClient] = [:]
    var onReady: (() -> Void)?

    init(key: String? = nil, receiver: MacClipboardReceiver? = nil,
         port: UInt16 = defaultPort, defaults: UserDefaults? = .standard,
         shortcutData: Data? = nil) {
        self.key = key
        self.receiver = receiver ?? MacClipboardReceiver()
        self.requestedPort = port
        self.defaults = defaults
        self.shortcutData = shortcutData ?? Bundle.main.url(forResource: "SendClipboardToMac", withExtension: "shortcut")
            .flatMap { try? Data(contentsOf: $0) }
    }

    func restoreEnabledState() {
        if defaults?.bool(forKey: Self.enabledPreference) == true { setEnabled(true) }
    }

    var pairingURL: String? {
        guard let port, let key,
              let host = SCDynamicStoreCopyLocalHostName(nil) as String? else { return nil }
        return "http://\(host).local:\(port)/\(key)/clipboard"
    }

    var pairingPageURL: String? {
        pairingURL.map { String($0.dropLast("clipboard".count)) + "setup" }
    }

    func setEnabled(_ value: Bool) {
        defaults?.set(value, forKey: Self.enabledPreference)
        enabled = value
        if value { start() } else { stop() }
    }

    private func start() {
        guard listener == nil else { return }
        do {
            if key == nil { key = try Self.loadOrCreateKey() }
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: requestedPort)!)
            self.listener = listener
            status = "正在启动…"
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready:
                        self.port = listener.port?.rawValue
                        self.status = "等待 iPad 手动发送"
                        self.onReady?()
                    case .failed:
                        self.stop()
                        self.status = "无法启动接收，请关闭后重试，并检查本地网络权限或端口占用。"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                Task { @MainActor in
                    guard let self, self.listener === listener, self.enabled,
                          self.clients.count < 8, let key = self.key else {
                        connection.cancel()
                        return
                    }
                    let id = UUID()
                    let client = ClipboardHTTPClient(connection: connection, key: key) { [weak self] request in
                        guard let self, self.enabled else { throw ClipboardTransferError.missingPeer }
                        switch request.action {
                        case .copy(let transfer):
                            if try self.receiver.receive(transfer, from: "paired-shortcut") {
                                self.receivedCount += 1
                                self.lastReceivedAt = Date()
                                self.status = "已复制到 Mac，可按 ⌘V 粘贴"
                            }
                            return ClipboardHTTPRequest.response(status: 200, message: "已复制到 Mac，可按 ⌘V 粘贴。")
                        case .setup:
                            return ClipboardHTTPRequest.contentResponse(type: "text/html; charset=utf-8", body: ClipboardPairingPage.data)
                        case .shortcut:
                            guard let data = self.shortcutData else {
                                return ClipboardHTTPRequest.response(status: 503, message: "快捷指令文件缺失，请更新 Mac 应用后重试。")
                            }
                            return ClipboardHTTPRequest.contentResponse(type: "application/x-apple-shortcut", body: data, attachment: true)
                        }
                    } onFinish: { [weak self] in self?.clients.removeValue(forKey: id) }
                    self.clients[id] = client
                    client.start()
                }
            }
            listener.start(queue: .main)
        } catch {
            status = "无法启动接收，请检查本地配置和端口占用。"
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        let active = Array(clients.values)
        clients.removeAll()
        active.forEach { $0.cancel() }
        status = "已关闭"
    }

    private static func loadOrCreateKey() throws -> String {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenDisplay FPS Lab/Clipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("pairing-key")
        if FileManager.default.fileExists(atPath: file.path) {
            let key = try String(contentsOf: file, encoding: .utf8)
            guard key.utf8.count == 64,
                  key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return key
        }
        let key = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        try key.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return key
    }
}

@MainActor
private final class ClipboardHTTPClient {
    private let connection: NWConnection
    private let key: String
    private let apply: (ClipboardHTTPRequest) throws -> Data
    private let onFinish: () -> Void
    private var buffer = Data()
    private var completed = false
    private var timeout: Task<Void, Never>?

    init(connection: NWConnection, key: String,
         apply: @escaping (ClipboardHTTPRequest) throws -> Data, onFinish: @escaping () -> Void) {
        self.connection = connection
        self.key = key
        self.apply = apply
        self.onFinish = onFinish
    }

    func start() {
        connection.start(queue: .main)
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.cancel()
        }
        receive()
    }

    func cancel() {
        guard !completed else { return }
        completed = true
        timeout?.cancel()
        connection.cancel()
        onFinish()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, eof, error in
            Task { @MainActor in
                guard let self, !self.completed else { return }
                if let data { self.buffer.append(data) }
                do {
                    if let request = try ClipboardHTTPRequest.parse(self.buffer, key: self.key) {
                        do {
                            let response = try self.apply(request)
                            self.send(response)
                        } catch {
                            self.respond(status: 503, message: "Clipboard unavailable")
                        }
                    } else if eof || error != nil {
                        self.cancel()
                    } else {
                        self.receive()
                    }
                } catch let failure as ClipboardHTTPRequest.Failure {
                    self.respond(status: failure.status, message: failure.message)
                } catch {
                    self.respond(status: 400, message: "Invalid request")
                }
            }
        }
    }

    private func respond(status: Int, message: String) {
        send(ClipboardHTTPRequest.response(status: status, message: message))
    }

    private func send(_ response: Data) {
        connection.send(content: response,
                        completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        })
    }
}
