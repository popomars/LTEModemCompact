import Foundation
import SystemConfiguration
import Security

public enum NetworkPreference: String, Sendable { case wifi, cellular }
public struct NetworkPriorityState: Sendable {
    public var summary: String
    public var canPreferWiFi: Bool
    public var canPreferCellular: Bool
    public var canRestore: Bool
    public var detail: String
    public init(summary: String, canPreferWiFi: Bool, canPreferCellular: Bool, canRestore: Bool, detail: String) {
        self.summary = summary; self.canPreferWiFi = canPreferWiFi; self.canPreferCellular = canPreferCellular
        self.canRestore = canRestore; self.detail = detail
    }
    public static let unavailable = NetworkPriorityState(summary: "正在读取网络服务…", canPreferWiFi: false, canPreferCellular: false, canRestore: false, detail: "")
}
public enum NetworkPriorityError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

// Swap only these two slots. Other service positions and their relative order stay unchanged.
public enum ServiceOrderPlan {
    public static func prefer(_ preferred: String, over other: String, in order: [String]) throws -> [String] {
        guard Set(order).count == order.count, preferred != other,
              let a = order.firstIndex(of: preferred), let b = order.firstIndex(of: other) else {
            throw NetworkPriorityError.message("网络服务顺序不完整或有歧义；未作修改")
        }
        var next = order
        if a > b { next.swapAt(a, b) }
        return next
    }
    public static func restore(current: [String], after: [String], before: [String], sameLocation: Bool) throws -> [String] {
        guard sameLocation, current == after, Set(before) == Set(after), Set(before).count == before.count else {
            throw NetworkPriorityError.message("网络位置或服务顺序已被其他操作更改，不能安全恢复旧顺序")
        }
        return before
    }
}

private struct PriorityBackup: Codable {
    let location: String
    let before: [String]
    let after: [String]
}
private struct ServiceLayout {
    let location: String
    let order: [String]
    let wifi: String?
    let cellular: String?
    let wifiReady: Bool
    let cellularReady: Bool
}

// Only explicit UI actions enter apply/restore. No privileged daemon or shell commands.
public enum NetworkPriority {
    private static func backupURL(_ directory: URL) -> URL { directory.appendingPathComponent("network-priority-backup.json") }
    private static func layout(_ set: SCNetworkSet) throws -> ServiceLayout {
        guard let order = SCNetworkSetGetServiceOrder(set) as? [String], !order.isEmpty,
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { throw NetworkPriorityError.message("无法读取当前网络服务顺序") }
        let store = SCDynamicStoreCreate(nil, "LTEModemCompact.Priority" as CFString, nil, nil)
        var wifi: [(String, Bool)] = [], cellular: [(String, Bool)] = []
        let network = NetworkMonitor.read()
        for service in services where SCNetworkServiceGetEnabled(service) {
            guard let interface = SCNetworkServiceGetInterface(service), let name = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            guard let id = SCNetworkServiceGetServiceID(service) as String?, order.contains(id) else { continue }
            let link = NetworkMonitor.link(name, store: store)
            let ready = link.active && link.hasAddress
            if SCNetworkInterfaceGetInterfaceType(interface) == kSCNetworkInterfaceTypeIEEE80211 { wifi.append((id, ready)) }
            if NetworkMonitor.modemInterface(interface) && ready { cellular.append((id, true)) }
        }
        let w = wifi.count == 1 ? wifi.first : nil
        let c = network.deviceCount == 1 && cellular.count == 1 ? cellular.first : nil
        guard let location = SCNetworkSetGetSetID(set) as String? else { throw NetworkPriorityError.message("无法识别网络位置") }
        return ServiceLayout(location: location, order: order, wifi: w?.0, cellular: c?.0, wifiReady: w?.1 ?? false, cellularReady: c?.1 ?? false)
    }
    public static func read(directory: URL) -> NetworkPriorityState {
        do {
            guard let prefs = SCPreferencesCreate(nil, "LTEModemCompact.Priority" as CFString, nil), let set = SCNetworkSetCopyCurrent(prefs) else { throw NetworkPriorityError.message("无法读取系统网络配置") }
            let state = try layout(set)
            var summary = "等待 Wi-Fi 和一只已取得地址的模块"
            if let wifi = state.wifi, let cellular = state.cellular,
               let a = state.order.firstIndex(of: wifi), let b = state.order.firstIndex(of: cellular) {
                summary = a < b ? "Wi-Fi 优先于当前模块" : "当前模块优先于 Wi-Fi"
            }
            let backup = try? JSONDecoder().decode(PriorityBackup.self, from: Data(contentsOf: backupURL(directory)))
            let canRestore = backup.map { $0.location == state.location && $0.after == state.order } ?? false
            return NetworkPriorityState(summary: summary, canPreferWiFi: state.wifiReady && state.cellular != nil,
                                        canPreferCellular: state.cellularReady && state.wifi != nil, canRestore: canRestore,
                                        detail: "只调整 Wi-Fi 与当前模块的先后顺序。其他服务和 Clash/VPN 设置保持不变；实际出口仍可能由它们决定。")
        } catch { return NetworkPriorityState(summary: "暂时不能切换", canPreferWiFi: false, canPreferCellular: false, canRestore: false, detail: error.localizedDescription) }
    }
    public static func apply(_ preference: NetworkPreference, directory: URL) throws {
        try transaction(directory: directory, restoring: false) { state in
            guard let wifi = state.wifi, let cellular = state.cellular,
                  preference == .wifi ? state.wifiReady : state.cellularReady else {
                throw NetworkPriorityError.message("目标网卡未就绪或线路有歧义；未作修改")
            }
            return try ServiceOrderPlan.prefer(preference == .wifi ? wifi : cellular, over: preference == .wifi ? cellular : wifi, in: state.order)
        }
    }
    public static func restore(directory: URL) throws {
        let backup = try JSONDecoder().decode(PriorityBackup.self, from: Data(contentsOf: backupURL(directory)))
        try transaction(directory: directory, restoring: true) { state in
            try ServiceOrderPlan.restore(current: state.order, after: backup.after, before: backup.before, sameLocation: state.location == backup.location)
        }
    }
    private static func transaction(directory: URL, restoring: Bool, plan: (ServiceLayout) throws -> [String]) throws {
        var auth: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &auth) == errAuthorizationSuccess, let auth else { throw NetworkPriorityError.message("无法创建系统网络授权请求") }
        defer { AuthorizationFree(auth, []) }
        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "LTEModemCompact" as CFString, nil, auth) else { throw NetworkPriorityError.message("无法打开系统网络配置") }
        guard SCPreferencesLock(prefs, false) else { throw NetworkPriorityError.message("网络设置正在被其他程序使用或未获授权，请稍后重试") }
        defer { SCPreferencesUnlock(prefs) }
        guard let set = SCNetworkSetCopyCurrent(prefs) else { throw NetworkPriorityError.message("没有当前网络位置") }
        let state = try layout(set)
        let next = try plan(state)
        guard next != state.order else { return }
        if !restoring {
            let backup = PriorityBackup(location: state.location, before: state.order, after: next)
            let url = backupURL(directory)
            try JSONEncoder().encode(backup).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        guard SCNetworkSetSetServiceOrder(set, next as CFArray), SCPreferencesCommitChanges(prefs) else {
            throw NetworkPriorityError.message("系统未保存切换；可能是授权取消或配置已变化")
        }
        guard SCPreferencesApplyChanges(prefs) else {
            let staged = SCNetworkSetSetServiceOrder(set, state.order as CFArray)
            let committed = staged && SCPreferencesCommitChanges(prefs)
            let applied = committed && SCPreferencesApplyChanges(prefs)
            throw NetworkPriorityError.message(applied ? "切换未能生效，已恢复原顺序" : "系统应用设置失败；请在系统网络设置中核对顺序")
        }
        guard let verify = SCPreferencesCreate(nil, "LTEModemCompact.Verify" as CFString, nil),
              let fresh = SCNetworkSetCopyCurrent(verify), (SCNetworkSetGetServiceOrder(fresh) as? [String]) == next else {
            throw NetworkPriorityError.message("保存后未能确认顺序，请刷新检查；未宣称切换成功")
        }
        if restoring { try? FileManager.default.removeItem(at: backupURL(directory)) }
    }
}
