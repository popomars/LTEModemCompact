import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import ModemCore
import NetworkCore

enum WorkspaceSection: String, CaseIterable { case sms = "短信", network = "网卡" }

@MainActor final class Controller: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var snapshot = ModemSnapshot(status: "正在启动后台…", sim: nil, carrier: "", registered: false, network: "", messages: [], newMessages: [])
    @Published var section: WorkspaceSection = .sms
    @Published var network = NetworkSnapshot.preview
    @Published var priority = NetworkPriorityState.unavailable
    @Published var networkBusy = false
    @Published var networkNotice = ""
    @Published var traffic = TrafficSnapshot()
    @Published var notificationStatus = "正在读取通知权限…"
    @Published var notificationsAuthorized = false
    @Published var notificationNeedsPermission = true
    @Published var notificationBusy = false
    @Published var notificationNotice = ""
    @Published var notificationEnabled = UserDefaults.standard.object(forKey: "smsNotificationsEnabled") as? Bool ?? true
    @Published var notificationSound = UserDefaults.standard.object(forKey: "smsNotificationSound") as? Bool ?? true
    @Published var notificationMessageID: String?
    private let trafficTracker: TrafficTracker
    private var networkRefreshing = false
    private let directory: URL
    private var networkTask: Task<Void, Never>?
    @Published var error = ""
    @Published var sending = false
    @Published var loginStatus = ""
    let demo: Bool
    private let engine: ModemEngine
    private var task: Task<Void, Never>?
    var onStatus: ((String) -> Void)?
    var onOpen: (() -> Void)?
    var sleeping = false
    init(directory: URL, demo: Bool) throws {
        self.demo = demo
        self.directory = directory
        self.network = demo ? .preview : NetworkMonitor.read()
        engine = try ModemEngine(directory: directory)
        trafficTracker = TrafficTracker(directory: directory)
        super.init()
    }
    func start() {
        if demo {
            snapshot = ModemSnapshot(status: "演示模式 · 未访问设备", sim: "demo", carrier: "中国联通", registered: true, network: "en15 · 192.0.2.2 · 示例本地链路", messages: [], newMessages: [])
            network = .preview
            priority = NetworkPriorityState(summary: "Wi-Fi 优先 · 演示", canPreferWiFi: false, canPreferCellular: false, canRestore: false, detail: "演示模式不会修改系统网络")
            notificationStatus = "演示模式 · 不发送通知"
            onStatus?(snapshot.status); return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "回复", options: [], textInputButtonTitle: "发送", textInputPlaceholder: "短信内容")
        center.setNotificationCategories([UNNotificationCategory(identifier: "incomingSMS", actions: [reply], intentIdentifiers: [], options: [])])
        task = Task { [weak self] in
            while !Task.isCancelled {
                if let self, !self.sleeping {
                    let next = await self.engine.poll()
                    guard !Task.isCancelled else { return }
                    self.snapshot = next; self.onStatus?(next.status)
                    for message in next.newMessages { await self.notify(message) }
                }
                do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            }
        }
        networkTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, !self.sleeping { await self.refreshNetwork() }
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            }
        }
        // Permissions and login startup remain explicit user choices.
        refreshLogin()
        Task { await refreshNotifications() }
    }
    func refreshNetwork() async {
        guard !demo, !networkRefreshing, !sleeping else { return }
        networkRefreshing = true
        defer { networkRefreshing = false }
        let directory = self.directory
        let values = await Task.detached(priority: .utility) {
            let network = NetworkMonitor.read()
            let counters = TrafficMonitor.read(names: network.links.filter(\.active).map(\.name))
            return (network, NetworkPriority.read(directory: directory), counters, ProcessInfo.processInfo.systemUptime)
        }.value
        guard !Task.isCancelled, !sleeping else { return }
        network = values.0; priority = values.1
        traffic = await trafficTracker.sample(values.2, uptime: values.3)
    }
    func resetTraffic() {
        guard !demo else { return }
        Task {
            do { traffic = try await trafficTracker.reset() }
            catch { self.error = "清零失败：\(error.localizedDescription)" }
        }
    }
    func setNetworkPreference(_ preference: NetworkPreference?) {
        guard !demo, !networkBusy else { return }
        networkBusy = true; networkNotice = "等待系统应用网络设置…"
        let directory = self.directory
        Task {
            defer { networkBusy = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    if let preference { try NetworkPriority.apply(preference, directory: directory) }
                    else { try NetworkPriority.restore(directory: directory) }
                }.value
                networkNotice = preference == nil ? "已恢复上次切换前的顺序" : "网络服务优先级已保存；实际出口请查看系统主接口，VPN/分流可能另行选择路径"
            } catch { networkNotice = error.localizedDescription }
            await refreshNetwork()
        }
    }
    func refreshLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "登录自动启动：已启用"
        case .requiresApproval: loginStatus = "登录自动启动：等待系统批准"
        case .notRegistered: loginStatus = "登录自动启动：未启用"
        case .notFound: loginStatus = "登录自动启动：应用位置或签名不可用"
        @unknown default: loginStatus = "登录自动启动：状态未知"
        }
    }
    func enableLogin() {
        guard !demo else { return }
        do { try SMAppService.mainApp.register(); refreshLogin() }
        catch { refreshLogin(); self.error = "后台启动注册失败：\(error.localizedDescription)" }
    }
    func disableLogin() {
        guard !demo else { return }
        Task {
            do { try await SMAppService.mainApp.unregister(); refreshLogin() }
            catch { self.error = "取消自动启动失败：\(error.localizedDescription)" }
        }
    }
    func send(to number: String, text: String, sim: String) async -> Bool {
        guard !demo else { error = "演示模式不会发送短信"; return false }
        guard !sending else { return false }
        sending = true; error = ""
        defer { sending = false }
        do { snapshot = try await engine.send(to: number, text: text, expectedSIM: sim); return true }
        catch { self.error = error.localizedDescription; snapshot = await engine.current(); return false }
    }
    func notify(_ message: Message) async {
        guard notificationEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "收到短信"
        // Avoid putting private SMS bodies or verification codes on the lock screen.
        content.body = "点击查看；展开可快捷回复"
        content.categoryIdentifier = "incomingSMS"
        content.userInfo = ["messageID": message.id]
        content.sound = notificationSound ? .default : nil
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: message.id, content: content, trigger: nil)) }
        catch { self.error = "短信已保存，通知发送失败：\(error.localizedDescription)" }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["messageID"] as? String
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            if let id { self.notificationMessageID = id }
            self.section = .sms
            if action == "reply", let id, let text {
                do {
                    let (peer, sim) = try await self.engine.replyTarget(id: id)
                    let sent = await self.send(to: peer, text: text, sim: sim)
                    let result = UNMutableNotificationContent()
                    result.title = sent ? "短信已提交给模块" : "短信回复未确认"
                    result.body = sent ? "送达尚未确认；可点击查看记录" : self.error
                    try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: result, trigger: nil))
                } catch { self.error = error.localizedDescription; self.onOpen?() }
            } else if action == UNNotificationDefaultActionIdentifier { self.onOpen?() }
        }
    }
    func stop() async { networkTask?.cancel(); networkTask = nil; task?.cancel(); task = nil; await engine.disconnect() }
    func releaseForSleep() { sleeping = true; Task { await trafficTracker.suspend(); await engine.disconnect() } }
}
