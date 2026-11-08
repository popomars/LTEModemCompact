import SwiftUI
import AppKit
import ServiceManagement
import ModemCore

struct WorkspaceView: View {
    @ObservedObject var controller: Controller
    @State private var selection: String?
    @State private var recipient = ""
    @State private var bodyText = ""
    @State private var showSettings = false
    @State private var showAllSIMs = false
    private var visibleMessages: [Message] { controller.snapshot.messages.filter { showAllSIMs || $0.sim == controller.snapshot.sim } }
    @State private var confirmSend = false
    @State private var pendingSIM: String?
    @State private var pendingRecipient = ""
    @State private var pendingText = ""
    private var selected: Message? { controller.snapshot.messages.first { $0.id == selection } }
    private var segmentCount: Int? { (try? SMSCodec.encode(to: recipient, text: bodyText))?.count }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("LTEModemCompact").font(.headline)
                    Text(controller.snapshot.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Button { showSettings.toggle(); controller.refreshLogin() } label: { Image(systemName: "gearshape") }.help("后台与通知设置")
            }.padding(18)
            Divider()
            if showSettings { settings }
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Text("短信").font(.headline); Spacer(); Button { selection = nil; recipient = ""; bodyText = "" } label: { Image(systemName: "square.and.pencil") }.help("新短信") }.padding(12)
                    Toggle("显示其他 SIM 与归属未核实的历史", isOn: $showAllSIMs).font(.caption).padding(.horizontal, 12)
                    List(visibleMessages, selection: $selection) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(message.peer).fontWeight(.medium); Spacer(); if message.sim != controller.snapshot.sim { Image(systemName: "simcard").help(message.sim == "unassigned" ? "原 SIM 归属未核实" : "来自其他 SIM 的历史记录") } }
                            Text(message.text).lineLimit(2).foregroundStyle(.secondary)
                            Text(message.date, style: .date).font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4).tag(message.id)
                    }
                }.frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                VStack(alignment: .leading, spacing: 14) {
                    if let message = selected {
                        Text(message.peer).font(.title2)
                        Text(message.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        ScrollView { Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 100)
                        Text(message.state.title + (message.state == .received && !message.complete ? " · 已收到 \(message.parts.count)/\(message.totalParts) 段" : "")).font(.caption).foregroundStyle(.secondary)
                        if !message.detail.isEmpty { Text(message.detail).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                        if message.state == .received {
                            Button("回复这条短信") { recipient = message.peer; bodyText = "" }
                                .disabled(message.sim != controller.snapshot.sim || !message.complete)
                        }
                        Divider()
                    } else {
                        Text("写短信").font(.title2)
                        Text("短信直接通过当前 USB 模块的 SIM 发送。").font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                    }
                    TextField("收件号码，例如 138… 或 +86…", text: $recipient).textFieldStyle(.roundedBorder).accessibilityLabel("收件号码")
                    TextEditor(text: $bodyText).accessibilityLabel("短信正文").font(.body).frame(minHeight: 100, maxHeight: 160).padding(6).background(.background).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    HStack {
                        Text(segmentCount.map { "\($0) 段短信 · 可能按段计费" } ?? "支持中文和英文").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(controller.sending ? "正在提交…" : "发送") {
                            pendingSIM = controller.snapshot.sim; pendingRecipient = recipient; pendingText = bodyText; confirmSend = true
                        }.buttonStyle(.borderedProminent).disabled(controller.sending || !controller.snapshot.canSend || segmentCount == nil)
                    }
                }.padding(22).frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if !controller.error.isEmpty {
                Divider(); HStack { Image(systemName: "exclamationmark.circle"); Text(controller.error).textSelection(.enabled); Spacer(); Button("关闭") { controller.error = "" } }.font(.caption).foregroundStyle(.orange).padding(12)
            }
            Divider()
            HStack {
                Image(systemName: "network"); Text(controller.snapshot.network).lineLimit(2)
                Spacer(); Text("关闭窗口后继续后台待命")
            }.font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .frame(minWidth: 780, minHeight: 560)
        .onChange(of: controller.snapshot.sim) { _ in selection = nil; recipient = ""; bodyText = ""; confirmSend = false }
        .onChange(of: showAllSIMs) { _ in selection = nil }
        .confirmationDialog("发送短信给 \(pendingRecipient)？", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("发送 \((try? SMSCodec.encode(to: pendingRecipient, text: pendingText))?.count ?? 0) 段短信") {
                guard let sim = pendingSIM else { return }
                Task { if await controller.send(to: pendingRecipient, text: pendingText, sim: sim) { bodyText = "" } }
            }
        } message: { Text("将通过当前 SIM 发送，可能产生运营商费用。超时不会自动重发。") }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.loginStatus).font(.callout)
            HStack {
                Button("启用登录自动启动") { controller.enableLogin() }
                Button("关闭自动启动") { controller.disableLogin() }
                Button("打开系统登录项设置") { SMAppService.openSystemSettingsLoginItems() }
                Button("允许短信通知") { controller.retryNotifications() }
            }
            Text("网卡由 macOS 管理，程序不会改变 Wi-Fi、VPN 或服务优先级。语音功能尚未实现。首次导入旧短信不弹通知，不删除模块短信。").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3))
    }
}
