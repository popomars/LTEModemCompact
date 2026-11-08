# 架构

## 组件

| 目录 | 职责 |
| --- | --- |
| `Sources/NativeUSB` | 自研 C / IOKit 接口枚举、非抢占式打开、超时读写和释放 |
| `Sources/LaunchSupport` / `USBLaunchEvents` / `USBLauncher` | 默认关闭的 USB 事件启动策略、XPC 桥接及随包助手 |
| `Sources/SystemNetworkStats` | 只读获取 Darwin 网卡 64 位累计计数 |
| `Sources/NetworkCore` | 系统网卡状态、流量累计与显式网络优先级事务，不打开 AT |
| `Sources/ModemCore` | 串行 AT 会话、短信编解码、存储和 SIM 生命周期 |
| `Sources/LTEModemCompact` | AppKit 菜单栏、SwiftUI 短信窗口、通知和用户自选登录项 |
| `Sources/ModemDiagnostics` | 与 GUI 共用引擎、存储和进程锁的有限诊断入口 |
| `Tests/ModemCoreTests` | 合成通道和协议夹具，不连接 USB、不发送真实短信 |

应用运行依赖仅为苹果系统框架和系统 Swift 库。Swift Package 没有外部依赖，也不引用父目录。公开仓库不包含任何第三方项目代码、社区内核模块、PCM helper 或 ADB。

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

仅在用户确认初始化/恢复时，按严格设备白名单备份并设置 ECM 网络模式、回读与请求重启；不设置 ADB、APN、IMS 或固件，也不包含语音通路。仅在用户点击切换按钮时，通过 Authorization Services 和 SCPreferences 对调 Wi-Fi 与当前模块的服务位置；其他服务和代理/VPN 设置不变。已配置 ECM 的网络连接由 macOS 自带驱动管理；应用退出不会主动断开它。

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

## 安装包外观

`scripts/render-installer-assets.swift` 用 AppKit 绘制原创图标和两倍分辨率的安装背景；构建时生成 ICNS，签名前装入应用；签名前移除可执行文件中的调试符号与对象映射，避免携带本机构建路径。图片不依赖外部下载，生成文件仅留在 `dist`。

`scripts/configure-dmg-layout.py` 在临时可写镜像中写入 Finder 窗口大小、背景别名及图标位置，再转成只读压缩 DMG。仅构建阶段使用 [ds-store](https://ds-store.readthedocs.io/en/latest/) 1.3.3 和 mac-alias 2.2.2；不复制其源码或运行环境到公开仓库、应用或镜像。构建不控制 Finder，也不改用户的 Finder 偏好。

## 流量与通知

流量通过 `NET_RT_IFLIST2` / `if_msghdr2` 读取 64 位字节计数，仅给已识别且活动的模块接口采样。接口索引与最后状态变更时间构成计数代次；初次采样、代次改变、计数回退、断开及超过 15 秒的间隔仅建立基线。速率使用进程单调时钟，累计值单独原子保存，不恢复旧内核基线。损坏的累计文件保留并提示，只有用户确认清零后才覆盖。此统计不尝试推导运营商计费。

通知仍由 `UNUserNotificationCenter` 本地提交，无推送服务。初始化设置类别与委托但不主动申请权限；显式开启时申请 alert/sound，读取当前系统授权、横幅配置并显示状态。应用启用开关与声音偏好独立保存。测试提醒与短信消息使用不同标识；只有 `newMessages` 产生短信通知，历史与去重由 MessageStore 控制。点击携带 messageID 定位本地消息，不在通知正文暴露号码和正文。

- [Apple：通知授权与当前设置](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Apple XNU：网络接口结构](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/if.h)

## 可选 USB 插入启动

LaunchAgent plist 位于 Contents/Library/LaunchAgents，BundleProgram 指向 Contents/Library/LoginItems 内的助手 app。内层先签名，外层后签名，不使用外部共享实例或 root daemon。SMAppService 只在用户主动选择时注册；助手消耗 XPC 事件并核实 VID/PID 后才启动它所属的主 bundle，不接收任意路径或远程可执行内容。启动策略、错误模式默认关闭、重复事件和主程序已运行的抑制由独立测试覆盖。硬件入口 ISO 与部署试验完全独立于应用运行流程。

## 新模块配置事务

DeviceSetup 由同一 ModemEngine actor 串行调用；维护期间关闭原 AT 会话并暂停短信轮询及发送。检查产生一次性计划，执行前重新核对 USB 身份与完整设备状态。原配置以设备身份哈希隔离、私有落盘并同步回读，未知或冲突状态拒绝写入。只写 usbnet，回读正确后发送一次 CFUN 重启请求；不确定结果不自动重试。详见 [设备初始化](DEVICE-SETUP.md)。
