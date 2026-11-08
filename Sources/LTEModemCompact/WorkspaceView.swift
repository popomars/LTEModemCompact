import SwiftUI
import AppKit
import ServiceManagement
import ModemCore
import LaunchSupport

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
                Button { showSettings.toggle(); controller.refreshLogin(); controller.refreshDeviceLaunch(); Task { await controller.refreshNotifications() } } label: { Image(systemName: "gearshape") }.help("后台与通知设置")
            }.padding(18)
            Divider()
            HStack {
                Picker("功能", selection: $controller.section) {
                    ForEach(WorkspaceSection.allCases, id: \.self) { section in Text(section.rawValue).tag(section) }
                }.pickerStyle(.segmented).frame(width: 340)
                Spacer()
            }.padding(.horizontal, 18).padding(.vertical, 10)
            if controller.setupActive {
                HStack {
                    Label("初始化期间短信暂停", systemImage: "pause.circle")
                    Spacer()
                    Button("结束初始化并恢复短信") { controller.endSetup() }.disabled(controller.setupBusy)
                }.font(.callout).padding(12).background(.orange.opacity(0.1))
            }
            if controller.section == .setup {
                DeviceSetupPane(controller: controller)
            } else if controller.section == .network {
                NetworkPane(controller: controller)
            } else {
            HStack {
                Image(systemName: "bell.badge")
                Text(controller.notificationStatus).font(.caption)
                Spacer()
                if controller.notificationNeedsPermission || !controller.notificationEnabled {
                    Button("开启短信通知") { controller.retryNotifications() }.disabled(controller.demo || controller.notificationBusy)
                } else {
                    Button("通知设置…") { showSettings = true; Task { await controller.refreshNotifications() } }
                }
            }.padding(.horizontal, 18).padding(.vertical, 8).background(.quaternary.opacity(0.25))
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
                        }.buttonStyle(.borderedProminent).disabled(controller.setupActive || controller.sending || !controller.snapshot.canSend || segmentCount == nil)
                    }
                }.padding(22).frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            }
            if !controller.error.isEmpty {
                Divider(); HStack { Image(systemName: "exclamationmark.circle"); Text(controller.error).textSelection(.enabled); Spacer(); Button("关闭") { controller.error = "" } }.font(.caption).foregroundStyle(.orange).padding(12)
            }
            Divider()
            HStack {
                Image(systemName: "network"); Text(controller.network.network).lineLimit(2)
                Spacer(); Text("关闭窗口后继续后台待命")
            }.font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .frame(minWidth: 780, minHeight: 560)
        .sheet(isPresented: $showSettings) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("后台与通知设置").font(.title2)
                    Spacer()
                    Button("完成") { showSettings = false }.keyboardShortcut(.cancelAction)
                }
                settings
            }.padding(22).frame(width: 720)
        }
        .onAppear { selectNotification() }
        .onChange(of: controller.notificationMessageID) { _ in selectNotification() }
        .onChange(of: controller.snapshot.sim) { _ in selection = nil; recipient = ""; bodyText = ""; confirmSend = false; selectNotification() }
        .onChange(of: controller.snapshot.messages.count) { _ in selectNotification() }
        .onChange(of: showAllSIMs) { _ in
            if let selectedID = selection, !visibleMessages.contains(where: { $0.id == selectedID }) { selection = nil }
        }
        .confirmationDialog("发送短信给 \(pendingRecipient)？", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("发送 \((try? SMSCodec.encode(to: pendingRecipient, text: pendingText))?.count ?? 0) 段短信") {
                guard let sim = pendingSIM else { return }
                Task { if await controller.send(to: pendingRecipient, text: pendingText, sim: sim) { bodyText = "" } }
            }
        } message: { Text("将通过当前 SIM 发送，可能产生运营商费用。超时不会自动重发。") }
    }
    private func selectNotification() {
        guard let id = controller.notificationMessageID,
              let message = controller.snapshot.messages.first(where: { $0.id == id }) else { return }
        showAllSIMs = message.sim != controller.snapshot.sim
        selection = id
        controller.notificationMessageID = nil
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("插入模块时")
                Picker("插入模块时", selection: Binding(get: { controller.deviceLaunchMode }, set: { controller.setDeviceLaunchMode($0) })) {
                    ForEach(DeviceLaunchMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 200).disabled(controller.demo || controller.deviceLaunchBusy)
                if controller.deviceLaunchBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("GitHub 下载页") { controller.openDownloadPage() }
            }
            Text(controller.deviceLaunchStatus).font(.caption).foregroundStyle(.secondary)
            Text("首次开启可能需要在系统登录项中允许后台项目。它只响应受支持模块的插入事件；关闭可撤销注册。只用网卡无需启动应用。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(controller.loginStatus).font(.callout)
            HStack {
                Button("启用登录自动启动") { controller.enableLogin() }
                Button("关闭自动启动") { controller.disableLogin() }
                Button("打开系统登录项设置") { SMAppService.openSystemSettingsLoginItems() }

            }
            Divider()
            HStack {
                Toggle("新短信通知", isOn: Binding(get: { controller.notificationEnabled }, set: { controller.setNotificationsEnabled($0) }))
                Toggle("提示音", isOn: Binding(get: { controller.notificationSound }, set: { controller.setNotificationSound($0) }))
                Spacer()
                Button("允许通知") { controller.retryNotifications() }.disabled(controller.notificationBusy)
                Button("系统通知设置") { controller.openNotificationSettings() }
                Button("测试通知") { controller.testNotification() }.disabled(!controller.notificationsAuthorized || !controller.notificationEnabled || controller.notificationBusy)
            }.disabled(controller.demo)
            Text(controller.notificationStatus).font(.caption)
            if !controller.notificationNotice.isEmpty { Text(controller.notificationNotice).font(.caption).foregroundStyle(.secondary) }
            Text("提醒中隐藏号码和短信正文。应用需在后台运行；专注模式或系统横幅设置可能使提醒静音。测试通知不发送短信。").font(.caption).foregroundStyle(.secondary)
            Text("网卡由 macOS 管理，只有你点击网卡页的切换按钮才调整 Wi-Fi 与模块优先级；不会改变 VPN 设置。语音功能尚未实现。首次导入旧短信不弹通知，不删除模块短信。").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3))
    }
}
