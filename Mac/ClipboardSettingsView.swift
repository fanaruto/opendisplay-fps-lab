import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @ObservedObject var bridge: MacClipboardBridge
    @State private var showingPairing = false
    @State private var qrImage: NSImage?
    @State private var exportMessage: String?

    var body: some View {
        Section("剪贴板") {
            Toggle("接收 iPad 剪贴板（手动发送）", isOn: Binding(
                get: { bridge.enabled }, set: { bridge.setEnabled($0) }))
            Text("在 iPad 复制文字或链接，运行快捷指令，Mac 收到后即可粘贴。两台设备需在同一局域网。")
                .font(.caption).foregroundStyle(.secondary)

            if bridge.enabled {
                Text(bridge.status).font(.caption)
                if let date = bridge.lastReceivedAt {
                    Text("最近接收：\(date.formatted(date: .omitted, time: .standard)) · 本次已接收 \(bridge.receivedCount) 次")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(showingPairing ? "收起配对码" : "iPad 配对…") {
                        showingPairing.toggle()
                        refreshQRCode()
                    }
                    Button("导出快捷指令…", action: exportShortcut)
                }
                .controlSize(.small)
                .disabled(bridge.port == nil)

                if showingPairing, let image = qrImage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("用 iPad 相机扫码，按页面提示添加快捷指令。只需配对一次。")
                            .font(.caption)
                        Image(nsImage: image)
                            .interpolation(.none).resizable()
                            .frame(width: 184, height: 184)
                            .padding(12).background(.white)
                            .accessibilityLabel("iPad 剪贴板配对二维码")
                        Button("复制配对地址") {
                            guard let address = bridge.pairingURL else { return }
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(address, forType: .string)
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
                if let exportMessage {
                    Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: bridge.pairingPageURL) { refreshQRCode() }
    }

    private func refreshQRCode() {
        guard showingPairing, let address = bridge.pairingPageURL,
              let filter = CIFilter(name: "CIQRCodeGenerator", parameters: [
                "inputMessage": Data(address.utf8), "inputCorrectionLevel": "M"]),
              let output = filter.outputImage else {
            qrImage = nil
            return
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let image = CIContext().createCGImage(scaled, from: scaled.extent) else { return }
        qrImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func exportShortcut() {
        guard let source = Bundle.main.url(forResource: "SendClipboardToMac", withExtension: "shortcut") else {
            exportMessage = "快捷指令文件缺失，请更新 Mac 应用后重试。"
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "发送剪贴板到 Mac.shortcut"
        panel.allowedContentTypes = [UTType(filenameExtension: "shortcut") ?? .data]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try Data(contentsOf: source).write(to: destination, options: .atomic)
                exportMessage = "已导出，可用隔空投送发到 iPad。添加时填写本机配对地址。"
            } catch {
                exportMessage = "导出失败，请换一个可写的位置后重试。"
            }
        }
    }
}
