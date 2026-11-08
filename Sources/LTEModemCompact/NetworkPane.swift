import SwiftUI
import NetworkCore

struct NetworkPane: View {
    @ObservedObject var controller: Controller
    @State private var confirmResetTraffic = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("网卡与上网").font(.title2).fontWeight(.semibold)
                        Text("USB 模块由 macOS 原生 ECM 驱动管理，无需拨号。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新状态") { Task { await controller.refreshNetwork() } }.disabled(controller.networkBusy || controller.demo)
                }
                GroupBox("连接状态") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(controller.network.status, systemImage: controller.network.hasLocalAddress ? "checkmark.circle.fill" : "network")
                            .foregroundStyle(controller.network.hasLocalAddress ? Color.green : Color.secondary)
                        if !controller.snapshot.carrier.isEmpty { row("运营商", controller.snapshot.carrier) }
                        ForEach(controller.network.links) { link in
                            VStack(alignment: .leading, spacing: 6) {
                                row("网卡", link.name + (link.active ? " · 已连接" : " · 未连接"))
                                row("IPv4 地址", link.addresses.isEmpty ? "等待分配" : link.addresses.joined(separator: ", "))
                                if let router = link.router { row("网关", router) }
                            }
                        }
                        Text("取得本地地址只证明 USB 链路已建立。当前页面不将它标记为 4G 互联网验证成功。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                GroupBox("网卡流量") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 30) {
                            rate("下载", controller.traffic.receiveRate, "arrow.down")
                            rate("上传", controller.traffic.sendRate, "arrow.up")
                            Spacer()
                            Button("清零统计…") { confirmResetTraffic = true }.disabled(controller.demo)
                        }
                        row("本次运行", "下载 " + bytes(controller.traffic.sessionReceived) + "  ·  上传 " + bytes(controller.traffic.sessionSent))
                        row("累计统计", "下载 " + bytes(controller.traffic.totalReceived) + "  ·  上传 " + bytes(controller.traffic.totalSent))
                        Text("累计起点：\(controller.traffic.since.formatted())").font(.caption).foregroundStyle(.secondary)
                        Text(controller.traffic.interfaces.isEmpty ? "等待模块网卡计数，速度暂为 0。" : "统计接口：" + controller.traffic.interfaces.joined(separator: "、")).font(.caption).foregroundStyle(.secondary)
                        Text("每约 5 秒刷新，统计应用运行且 Mac 唤醒期间模块网卡的收发字节；退出或休眠期间不补计。累计跨重启保留，多模块合计、不按 SIM 分账，含协议开销及本地链路流量，与运营商计费可能不同。").font(.caption).foregroundStyle(.secondary)
                        if !controller.traffic.notice.isEmpty { Text(controller.traffic.notice).font(.caption).foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                GroupBox("上网优先级") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(controller.priority.summary).font(.headline)
                        row("系统主接口", controller.network.primaryInterface ?? "尚未报告")
                        HStack(spacing: 10) {
                            Button("优先使用 Wi-Fi") { controller.setNetworkPreference(.wifi) }
                                .disabled(!controller.priority.canPreferWiFi || controller.networkBusy || controller.demo)
                            Button("优先使用 4G") { controller.setNetworkPreference(.cellular) }
                                .disabled(!controller.priority.canPreferCellular || controller.networkBusy || controller.demo)
                            Button("撤销上次切换") { controller.setNetworkPreference(nil) }
                                .disabled(!controller.priority.canRestore || controller.networkBusy || controller.demo)
                            if controller.networkBusy { ProgressView().controlSize(.small) }
                        }
                        Text(controller.priority.detail).font(.callout).foregroundStyle(.secondary)
                        Text("系统可能要求管理员授权。优先使用 4G 可能消耗 SIM 套餐流量；网卡没有地址时不能选作优先出口。").font(.caption).foregroundStyle(.secondary)
                        if !controller.networkNotice.isEmpty { Text(controller.networkNotice).font(.callout).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                Text("退出应用后网卡仍可联网；已保存的优先级也会保留。这里的选择只改变 Wi-Fi 与模块的相对优先级，其他更靠前的网络服务仍可能优先使用。").font(.caption).foregroundStyle(.secondary)
                Text("状态更新：\(controller.network.checkedAt.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 920, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("清零本次与累计流量？", isPresented: $confirmResetTraffic, titleVisibility: .visible) {
            Button("清零统计", role: .destructive) { controller.resetTraffic() }
        } message: { Text("只清除本机流量统计，不改变网络连接或 SIM 套餐。此操作不能撤销。") }
    }
    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .decimal)
    }
    private func rate(_ title: String, _ value: Double, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(bytes(UInt64(max(0, min(value, Double(Int64.max))))) + "/s").font(.title3.monospacedDigit())
        }.frame(minWidth: 130, alignment: .leading)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer(minLength: 0)
        }.font(.callout)
    }
}
