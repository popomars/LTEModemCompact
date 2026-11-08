import AppKit
import ServiceManagement
import LaunchSupport

extension Controller {
    func refreshDeviceLaunch() {
        guard !demo else { deviceLaunchStatus = "演示模式 · 不注册插入启动"; return }
        let service = SMAppService.agent(plistName: DeviceLaunchPolicy.serviceName)
        switch service.status {
        case .enabled: deviceLaunchStatus = deviceLaunchMode == .off ? "插入启动已关闭；后台注册待移除" : "插入启动已注册：" + deviceLaunchMode.title
        case .requiresApproval: deviceLaunchStatus = "等待系统批准，请在登录项设置中允许 LTEModemCompact 后台项目"
        case .notRegistered: deviceLaunchStatus = "插入启动尚未注册"
        case .notFound: deviceLaunchStatus = "启动组件未找到；请从完整安装包重新安装"
        @unknown default: deviceLaunchStatus = "插入启动状态未知"
        }
    }
    func setDeviceLaunchMode(_ mode: DeviceLaunchMode) {
        guard !demo, !deviceLaunchBusy else { return }
        let service = SMAppService.agent(plistName: DeviceLaunchPolicy.serviceName)
        let app = Bundle.main.bundleURL.standardizedFileURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
        guard mode == .off || app.hasPrefix("/Applications/") || app.hasPrefix(userApps) else {
            deviceLaunchStatus = "请先将应用拖入“应用程序”文件夹并从那里打开，再开启插入启动。"; return
        }
        deviceLaunchBusy = true
        let previous = deviceLaunchMode
        // Off takes effect even if macOS cannot immediately unregister the job.
        deviceLaunchMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DeviceLaunchPolicy.modeKey)
        UserDefaults.standard.synchronize()
        Task {
            defer { deviceLaunchBusy = false }
            do {
                if mode == .off {
                    if service.status != .notRegistered && service.status != .notFound { try await service.unregister() }
                } else if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
                refreshDeviceLaunch()
            } catch {
                if mode != .off {
                    deviceLaunchMode = previous
                    UserDefaults.standard.set(previous.rawValue, forKey: DeviceLaunchPolicy.modeKey)
                    UserDefaults.standard.synchronize()
                }
                deviceLaunchStatus = "插入启动设置未完成：\(error.localizedDescription)"
            }
        }
    }
    func openDownloadPage() { NSWorkspace.shared.open(DeviceLaunchPolicy.releases) }
}
