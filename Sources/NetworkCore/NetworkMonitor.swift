import Foundation
import SystemConfiguration
import NativeUSB

public struct NetworkSnapshot: Sendable {
    public let status: String
    public let network: String
    public let deviceCount: Int
    public let hasLocalAddress: Bool
    public let demo: Bool
    public static let preview = NetworkSnapshot(status: "演示模式 · 未访问设备", network: "en15 · 192.0.2.2 · 示例本地链路", deviceCount: 1, hasLocalAddress: true, demo: true)
}

// Milestone 1 has no AT session or SMS store. ECM operates independently;
// this optional helper only reads USB descriptors and system network state.
public enum NetworkMonitor {
    public static func read() -> NetworkSnapshot {
        let count = Int(nm_devices(nil, 0))
        guard count >= 0 else { return NetworkSnapshot(status: "USB 描述符暂不可读", network: "系统仍独立管理网卡", deviceCount: 0, hasLocalAddress: false, demo: false) }
        guard count > 0 else { return NetworkSnapshot(status: "等待插入模块", network: "联网由 macOS 原生 ECM 驱动管理", deviceCount: 0, hasLocalAddress: false, demo: false) }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let matches = interfaces.filter {
            let name = (SCNetworkInterfaceGetLocalizedDisplayName($0) as String? ?? "").lowercased()
            return name.contains("baiwang") || name.contains("quectel") || name.contains("qdc507")
        }
        let store = SCDynamicStoreCreate(nil, "LTEModemCompact.Network" as CFString, nil, nil)
        var hasAddress = false
        let lines = matches.map { interface in
            let name = SCNetworkInterfaceGetBSDName(interface) as String? ?? "ECM"
            let key = "State:/Network/Interface/\(name)/IPv4" as CFString
            let state = store.flatMap { SCDynamicStoreCopyValue($0, key) as? [String: Any] }
            let addresses = state?["Addresses"] as? [String] ?? []
            hasAddress = hasAddress || !addresses.isEmpty
            return addresses.isEmpty ? "\(name) · 等待 DHCP" : "\(name) · \(addresses.joined(separator: ", "))"
        }
        let status = count > 1 ? "检测到多个模块 · 仅显示系统链路" : (hasAddress ? "ECM 本地链路已建立" : "模块已连接 · 等待系统网卡")
        return NetworkSnapshot(status: status, network: lines.isEmpty ? "等待 macOS 枚举 ECM 网卡" : lines.joined(separator: "\n"), deviceCount: count, hasLocalAddress: hasAddress, demo: false)
    }
}
