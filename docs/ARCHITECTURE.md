# 架构

## 组件

| 目录 | 职责 |
| --- | --- |
| `Sources/NativeUSB` | 自研 C / IOKit 接口枚举、非抢占式打开、超时读写和释放 |
| `Sources/NetworkCore` | 系统网卡状态与显式网络优先级事务，不打开 AT |
| `Sources/ModemCore` | 串行 AT 会话、短信编解码、存储和 SIM 生命周期 |
| `Sources/LTEModemCompact` | AppKit 菜单栏、SwiftUI 短信窗口、通知和用户自选登录项 |
| `Sources/ModemDiagnostics` | 与 GUI 共用引擎、存储和进程锁的有限诊断入口 |
| `Tests/ModemCoreTests` | 合成通道和协议夹具，不连接 USB、不发送真实短信 |

依赖仅为苹果系统框架和系统 Swift 库。Swift Package 没有外部依赖，也不引用父目录。公开仓库不包含任何第三方项目代码、社区内核模块、PCM helper 或 ADB。

## 数据流

1. 枚举指定 USB 身份与接口；多设备时暂停。
2. 非抢占式打开 AT 接口，使用 ESC 取消可能遗留的输入提示，随后同步通道；恢复过程不发送 Ctrl-Z。
3. 核对型号、固件、SIM 和 LTE 注册状态。
4. 选择 PDU 短信模式，查询当前接收存储区；必要时只调整读取区。读取前后重新核对 SIM，再归档和去重。
5. GUI 获取快照；通知只针对后续完整新短信，首次导入保持静默。
6. 发送时复核 SIM，保存发送意图，逐段提交并落盘；结果不确定时断开会话，不自动重试。

`ModemEngine` 使用 actor 串行化设备操作。`ATSession` 处理拆分响应、提示符和错误终止行；C 层将两种正常 USB 超时视为空读取，其余错误返回供上层处理。应用与诊断工具共用本机文件锁；其他客户端仍可能占用接口，因此不尝试抢占。

## 编解码与持久化

接收实现 SMS-DELIVER、GSM7 默认/扩展表、UCS2，以及 8/16 位拼接头。发送使用 UCS2，只有显式 `+` 使用国际号码类型。不支持的二进制、压缩或国家语言转换表消息保留原始 PDU。

存储使用私有临时文件、同步写入和原子替换；重启后将尚未完成的发送标为不确定。长短信按 SIM、发送方、参考号、总段数和时间窗口拼接。该启发式不能解决所有参考号重用情形。

## 设备边界

不设置 ECM、ADB、APN、IMS 或固件，也不包含语音通路。仅在用户点击切换按钮时，通过 Authorization Services 和 SCPreferences 对调 Wi-Fi 与当前模块的服务位置；其他服务和代理/VPN 设置不变。已配置 ECM 的网络连接由 macOS 自带驱动管理；应用退出不会主动断开它。

当前接口和固件白名单较窄。扩展支持必须先检查描述符、端点和设备身份，再补充测试与兼容性记录；不得通过遍历所有 bulk 接口发送探测命令。

## 网络优先级事务

通过 `SCPreferencesCreateWithAuthorization` 使用 macOS 原生授权。先独占配置会话并重新读取目标服务，再保存私有撤销记录、提交并应用顺序，最后回读确认。应用失败尝试恢复原顺序；若恢复也失败，明确要求核对系统网络配置。撤销要求当前位置和顺序与上次写入一致，避免覆盖其他操作。没有 root 常驻进程或 shell 提权命令。

选择策略的测试覆盖其他服务不变、缺失/重复目标、外部改动后的撤销拒绝与自分配地址过滤；不将这些测试替代真实授权和实际路由验收。

## 参考

- [3GPP TS 23.040 / ETSI：SMS TPDU](https://www.etsi.org/deliver/etsi_ts/123000_123099/123040/19.00.00_60/ts_123040v190000p.pdf)
- [Quectel EC25/EC21 AT 手册](https://quectel.com/content/uploads/2021/03/Quectel_EC25EC21_AT_Commands_Manual_V1.3.pdf)：短信命令语义参考，不能替代 QDC507 真机适配。
- [Apple IOKit USB 文档](https://developer.apple.com/library/archive/documentation/DeviceDrivers/Conceptual/USBBook/USBIntro/USBIntro.html)
- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple 通知文本回复](https://developer.apple.com/documentation/usernotifications/untextinputnotificationaction)

- [Apple：SCPreferencesCreateWithAuthorization](https://developer.apple.com/documentation/systemconfiguration/scpreferencescreatewithauthorization(_:_:_:_:))
