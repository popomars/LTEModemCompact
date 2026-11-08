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
                GroupBox("开始前 · 准备好再连接") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("① 将应用装入“应用程序”，使用能传输数据的 USB 线，只连接一只模块。")
                        Text("② 正常退出其他模块管理软件；Mac 提示“允许配件连接”时点允许。")
                        Text("③ 初始化会短暂断开模块网络，建议先连接可用 Wi-Fi。准备使用短信或上网时，先断开 USB 再按卡槽标识装入有效 SIM。")
                        Text("无需 SIM 也能检查和初始化。下面的说明无需联网即可阅读。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("1 · 检查设备") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("点击下方按钮，只读取设备信息，不修改模块。检查期间短信暂停；离开这个页面不会自动恢复短信。")
                        HStack {
                            Button("检查设备") { controller.inspectSetup() }.disabled(controller.demo || controller.setupBusy || controller.sending)
                            if controller.setupBusy { ProgressView().controlSize(.small) }
                        }
                        if let report = controller.setupReport {
                            Text("型号：\(report.model)　固件：\(report.firmware)").textSelection(.enabled)
                            Text(report.usbMode == 1 ? "网络模式：ECM（已配置）" : "网络模式：出厂模式（需要初始化）")
                            Label(report.usbMode == 1 ? "无需重复初始化，直接前往第 3、4 步。" : "检查通过，请在第 2 步备份并启用 ECM。", systemImage: report.usbMode == 1 ? "checkmark.circle" : "arrow.down.circle")
                                .foregroundStyle(.tint)
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
                        if controller.setupBusy {
                            Label("正在处理设备，请保持连接并等待结果…", systemImage: "hourglass")
                        } else if controller.setupReport == nil {
                            Text("按钮暂不可用：请先检查设备；若检查失败，按下方“遇到问题怎么办”处理。")
                        }
                        Text("恢复按钮不是初始化的必要步骤。只有本机有这只模块的原配置备份时才可用；恢复后 Mac 可能不再识别网卡。")
                        Text("备份只属于当前模块。已经配置 ECM、但没有本机初始化备份的设备，不提供猜测式恢复。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("3 · 重启后复查") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("写入后模块会重启、暂时消失。操作处理中不要拔线；待操作结束、模块重新出现，再点击“检查设备”。看到“ECM（已配置）”才表示配置复查通过。")
                        Text("若提示“重启响应未确认”，先等待恢复，不要反复初始化。若模块一直未出现，可在操作结束后断开 USB，等 5 秒再接回并允许配件，然后重新检查。")
                        Button("重新检查设备") { controller.inspectSetup() }.disabled(controller.demo || controller.setupBusy || controller.sending)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("4 · 恢复短信并确认可用") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("先结束初始化以恢复短信后台，再到网卡页确认模块有地址。已有 ECM 配置的设备也可以从这里继续。")
                        HStack {
                            Button("结束初始化并恢复短信") { controller.endSetup() }.disabled(!controller.setupActive || controller.setupBusy)
                            Button("查看网卡状态") { controller.section = .network }
                        }
                        Text("有地址只代表 Mac 与模块之间连通，不代表已通过 4G 上网。准备好有效 SIM 后，如需验证 4G，在网卡页明确选择优先使用 4G，再访问网页；Clash/VPN 可能影响实际出口，测试后可恢复原优先级。")
                        Text("在短信页用你能核对收件的手机测试收发，可能产生套餐费用。只用网卡时可以退出应用；需要接收短信或通知时请保持应用运行。")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !controller.setupNotice.isEmpty { Text(controller.setupNotice).textSelection(.enabled).foregroundStyle(.secondary) }
                DisclosureGroup("遇到问题怎么办") {
                    VStack(alignment: .leading, spacing: 12) {
                        help("找不到设备 / 提示连接多只", "仅保留一只模块，检查数据线、USB 连接及配件允许提示；退出其他模块客户端，再重新检查。仍找不到时，不代表可以强制初始化。")
                        help("型号、固件或配置不支持", "当前仅支持内部型号 QDC507、固件 QDC507GLEFM21 及已验证接口组合。外壳型号相同也可能不同；请停止，不要尝试其他设备的配置。")
                        help("写入或回读未确认", "先重新检查当前状态，不要反复点击写入。显示 ECM 时进入第 3、4 步；有匹配的本机备份且需撤销时，再考虑恢复原网络模式。")
                        help("备份损坏或与设备不匹配", "保留原备份，不要删除或用其他模块的备份替换；停止操作。可在项目页报告不含隐私信息的错误提示。")
                        help("ECM 已配置，但没网或没短信", "初始化不会解锁 SIM 或补充套餐。检查卡片方向、是否在手机可用及信号；恢复短信后台后查看应用状态。不要用重复初始化解决 SIM 或运营商问题。")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                }
                Link("完整操作步骤与支持范围（GitHub，需联网）", destination: URL(string: "https://github.com/popomars/LTEModemCompact/blob/main/docs/DEVICE-SETUP.md")!)
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
    private func help(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary)
        }
    }
    private func prepare(restoring: Bool) {
        pendingToken = controller.setupReport?.token
        self.restoring = restoring
        confirm = pendingToken != nil
    }
}
