import Foundation

public enum DeviceLaunchMode: String, CaseIterable, Sendable {
    case off, ask, automatic
    public var title: String {
        switch self { case .off: return "关闭"; case .ask: return "先询问"; case .automatic: return "自动后台启动" }
    }
}
public enum DeviceLaunchPolicy {
    public static let defaultsSuite = "live.lepus.NativeModem"
    public static let modeKey = "usbInsertionLaunchMode"
    public static let serviceName = "live.lepus.NativeModem.USBLaunch.plist"
    public static let releases = URL(string: "https://github.com/popomars/LTEModemCompact/releases")!
    public static func mode(_ value: String?) -> DeviceLaunchMode { value.flatMap(DeviceLaunchMode.init(rawValue:)) ?? .off }
    public static func shouldHandle(mode: DeviceLaunchMode, supported: Bool, alreadyRunning: Bool,
                                    registryID: String, lastID: String?) -> Bool {
        mode != .off && supported && !alreadyRunning && registryID != lastID
    }
    public static func hostApplication(helper: URL) -> URL? {
        // Exactly the embedded helper layout, never an arbitrary path from an event.
        guard helper.lastPathComponent == "LTEModemCompact USB Launcher.app",
              helper.deletingLastPathComponent().lastPathComponent == "LoginItems" else { return nil }
        let host = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard host.pathExtension == "app" else { return nil }
        return host
    }
}
