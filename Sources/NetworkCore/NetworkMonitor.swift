import Foundation
import SystemConfiguration
import NativeUSB

public struct NetworkLink: Sendable, Identifiable {
    public let name: String
    public let addresses: [String]
    public let router: String?
    public let active: Bool
    public var id: String { name }
    public var hasAddress: Bool { addresses.contains { !$0.hasPrefix("169.254.") && $0 != "0.0.0.0" } }
}

public struct NetworkSnapshot: Sendable {
    public let status: String
    public let network: String
    public let deviceCount: Int
    public let hasLocalAddress: Bool
    public let demo: Bool
    public var links: [NetworkLink] = []
    public var primaryInterface: String? = nil
    public var checkedAt: Date = Date()
    public static let preview = NetworkSnapshot(status: "演示模式 · 本地链路已建立", network: "en15 · 192.0.2.2", deviceCount: 1, hasLocalAddress: true, demo: true, links: [NetworkLink(name: "en15", addresses: ["192.0.2.2"], router: "192.0.2.1", active: true)], primaryInterface: "en0")
}

// System state only. No AT, external requests or route changes.
public enum NetworkMonitor {
    static func modemInterface(_ interface: SCNetworkInterface) -> Bool {
        let name = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? "").lowercased()
        return name.contains("baiwang") || name.contains("quectel") || name.contains("qdc507")
    }
    static func link(_ name: String, store: SCDynamicStore?) -> NetworkLink {
        let ipv4 = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Interface/\(name)/IPv4" as CFString) as? [String: Any] } ?? [:]
        let physical = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Interface/\(name)/Link" as CFString) as? [String: Any] } ?? [:]
        let addresses = ipv4["Addresses"] as? [String] ?? []
        return NetworkLink(name: name, addresses: addresses, router: ipv4["Router"] as? String, active: physical["Active"] as? Bool ?? !addresses.isEmpty)
    }
    public static func read() -> NetworkSnapshot {
        let count = Int(nm_devices(nil, 0))
        let store = SCDynamicStoreCreate(nil, "LTEModemCompact.Network" as CFString, nil, nil)
        let global = store.flatMap { SCDynamicStoreCopyValue($0, "State:/Network/Global/IPv4" as CFString) as? [String: Any] }
        let primary = global?["PrimaryInterface"] as? String
        guard count > 0 else { return NetworkSnapshot(status: count < 0 ? "USB 描述符暂不可读" : "等待插入模块", network: "联网由 macOS 原生 ECM 驱动管理", deviceCount: max(count, 0), hasLocalAddress: false, demo: false, primaryInterface: primary) }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let names = Set(interfaces.filter(modemInterface).compactMap { SCNetworkInterfaceGetBSDName($0) as String? })
        let links = names.sorted().map { link($0, store: store) }
        let hasAddress = links.contains { $0.active && $0.hasAddress }
        let lines = links.map { item in
            !item.active ? "\(item.name) · 未连接" : item.hasAddress ? "\(item.name) · \(item.addresses.joined(separator: ", "))" : "\(item.name) · 等待 DHCP"
        }
        let status = count > 1 ? "检测到多个模块 · 仅显示系统链路" : hasAddress ? "ECM 本地链路已建立" : links.contains(where: \.active) ? "网卡已连接 · 等待地址" : "模块已连接 · 等待系统网卡"
        return NetworkSnapshot(status: status, network: lines.isEmpty ? "等待 macOS 枚举 ECM 网卡" : lines.joined(separator: "\n"), deviceCount: count, hasLocalAddress: hasAddress, demo: false, links: links, primaryInterface: primary)
    }
}
