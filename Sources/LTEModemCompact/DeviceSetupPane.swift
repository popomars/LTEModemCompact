import SwiftUI
import ModemCore

struct DeviceSetupPane: View {
    @ObservedObject var controller: Controller
    @State private var pendingToken: UUID?
    @State private var restoring = false
    @State private var confirm = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("让新的模块在 Mac 上使用", systemImage: "externaldrive.badge.plus").font(.title2)
                Text("只连接一只 IG830 或 IG832。应用先核实内部型号和固件，再决定是否能初始化；外壳型号相同不代表配置相同。无需插 SIM 即可检查。")
                GroupBox("1 · 检查设备") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前仅支持 QDC507 / QDC507GLEFM21 及已验证的 USB 接口组合。检查会暂停短信，并释放通信接口。")
                        HStack {
                            Button("检查设备") { controller.inspectSetup() }.disabled(controller.demo || controller.setupBusy || controller.sending)
                            if controller.setupBusy { ProgressView().controlSize(.small) }
                        }
                        if let report = controller.setupReport {
                            Text("型号：\(report.model)　固件：\(report.firmware)").textSelection(.enabled)
                            Text(report.usbMode == 1 ? "网络模式：ECM（已配置）" : "网络模式：出厂模式（需要初始化）")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("2 · 备份与初始化") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("将原配置备份到这台 Mac，然后启用 macOS 原生 ECM 网卡并重启模块。网卡会短暂断开；应用不会修改系统网络优先级。")
                        HStack {
                            Button("备份并启用 ECM…") { prepare(restoring: false) }
                                .buttonStyle(.borderedProminent)
                                .disabled(controller.setupBusy || controller.setupReport?.canEnableECM != true)
                            Button("恢复本机保存的原网络模式…") { prepare(restoring: true) }
                                .disabled(controller.setupBusy || controller.setupReport?.canRestore != true)
                        }
                        Text("备份只属于当前模块。已经配置 ECM、但没有本机初始化备份的设备，不提供猜测式恢复。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("3 · 重启后复查") {
                    Text("等待模块重新出现，再点击“检查设备”核实配置，并到“网卡”页确认地址。随后结束初始化，恢复短信。若接口未回来，请断电重插并允许配件连接。ECM 配置正确不等于已连通互联网，仍需有效 SIM、信号及运营商支持。")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !controller.setupNotice.isEmpty { Text(controller.setupNotice).textSelection(.enabled).foregroundStyle(.secondary) }
                Text("这是配置初始化，不是刷固件。当前不包含语音初始化、ADB 授权、安装入口盘部署或未知固件转换。短信由应用提供，语音尚未实现。").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .confirmationDialog(restoring ? "恢复原网络模式并重启模块？" : "启用 ECM 并重启模块？", isPresented: $confirm, titleVisibility: .visible) {
            Button(restoring ? "恢复并重启" : "备份、启用并重启", role: restoring ? .destructive : nil) {
                if let token = pendingToken { controller.applySetup(token: token, restoring: restoring) }
            }
        } message: {
            Text(restoring ? "会恢复本机记录的原网络模式，Mac 可能不再识别模块网卡。只恢复网络模式，不还原固件或其他设置。" : "ECM 设置会保留到以后拔插。应用会先保存原配置、回读核验，再请求模块重启；操作期间网卡和短信短暂中断。")
        }
    }
    private func prepare(restoring: Bool) {
        pendingToken = controller.setupReport?.token
        self.restoring = restoring
        confirm = pendingToken != nil
    }
}
