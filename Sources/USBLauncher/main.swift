import AppKit
import LaunchSupport
import USBLaunchEvents

// This helper never opens AT, changes routes, downloads code or reads SMS storage.
umask(0o077)
if ProcessInfo.processInfo.arguments.contains("--self-check") {
    let host = DeviceLaunchPolicy.hostApplication(helper: Bundle.main.bundleURL)
    let valid = Bundle.main.bundleIdentifier == "live.lepus.NativeModem.USBLauncher"
        && host.flatMap(Bundle.init(url:))?.bundleIdentifier == DeviceLaunchPolicy.defaultsSuite
    print(valid ? "Embedded bundle resolution: PASS; no events registered, no UI or USB access" : "Embedded bundle resolution: FAIL")
    exit(valid ? 0 : 1)
}
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let preferences = UserDefaults(suiteName: DeviceLaunchPolicy.defaultsSuite)!
var handling = false
var idleExit: DispatchWorkItem?
func finish() -> Never { exit(0) }
func scheduleIdleExit() {
    idleExit?.cancel()
    let work = DispatchWorkItem { if !handling { finish() } }
    idleExit = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
}
func handle(_ registryID: UInt64) {
    guard !handling else { return }
    let mode = DeviceLaunchPolicy.mode(preferences.string(forKey: DeviceLaunchPolicy.modeKey))
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: DeviceLaunchPolicy.defaultsSuite).contains { !$0.isTerminated }
    var count = 0
    sysctlbyname("kern.bootsessionuuid", nil, &count, nil, 0)
    var boot = [CChar](repeating: 0, count: max(count, 1))
    guard sysctlbyname("kern.bootsessionuuid", &boot, &count, nil, 0) == 0 else { finish() }
    let id = String(cString: boot) + ":" + String(registryID)
    guard DeviceLaunchPolicy.shouldHandle(mode: mode, supported: lte_is_supported_usb_device(registryID) != 0,
                                         alreadyRunning: running, registryID: id,
                                         lastID: preferences.string(forKey: "lastHandledUSBRegistryID")) else { return }
    guard let host = DeviceLaunchPolicy.hostApplication(helper: Bundle.main.bundleURL),
          Bundle(url: host)?.bundleIdentifier == DeviceLaunchPolicy.defaultsSuite else { finish() }
    handling = true
    preferences.set(id, forKey: "lastHandledUSBRegistryID")
    preferences.synchronize()
    if mode == .ask {
        let alert = NSAlert()
        alert.messageText = "已连接 LTE 模块"
        alert.informativeText = "是否打开 LTEModemCompact，以查看流量、收发短信并接收通知？只用网卡上网时无需打开。"
        alert.addButton(withTitle: "打开应用")
        alert.addButton(withTitle: "暂不打开")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { finish() }
    }
    preferences.synchronize()
    // A device may have been unplugged while the prompt was visible.
    guard lte_is_supported_usb_device(registryID) != 0,
          DeviceLaunchPolicy.mode(preferences.string(forKey: DeviceLaunchPolicy.modeKey)) != .off else { finish() }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = mode == .ask
    config.arguments = mode == .ask ? ["--show"] : []
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { finish() }
    NSWorkspace.shared.openApplication(at: host, configuration: config) { _, _ in
        DispatchQueue.main.async { finish() }
    }
}
lte_listen_usb_events { registryID in
    // Coalesce the enumeration burst without leaving a polling daemon resident.
    scheduleIdleExit()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { handle(registryID) }
}
scheduleIdleExit()
application.run()
