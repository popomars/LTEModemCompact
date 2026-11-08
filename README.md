# LTEModemCompact

面向 Apple Silicon Mac 的轻量 USB 蜂窝模块助手。原生 Swift + C 实现，只有苹果系统框架依赖，无第三方 Swift Package、后台服务或网络监听端口。

当前 **v0.2.0，开发预览版**：系统 ECM 联网、菜单栏状态和独立短信收发。语音尚未实现。

## 支持范围与当前进度

| 功能 | 状态 |
| --- | --- |
| 原生 ECM 网卡 | 已配置设备使用 macOS 自带驱动；退出应用仍可联网 |
| IG830 数据联网 | 移动卡、联通卡实测通过；一次断电重插恢复通过 |
| IG830 短信 | 联通卡中英文混合文本发送、中文接收、重启去重实测通过 |
| IG832 | 已适配相同 USB / 型号 / 固件范围；本项目短信仍待实测 |
| 长短信 | 已实现编解码与分段，单元测试通过，真实收发待验收 |
| 系统通知、快捷回复、登录启动 | 已实现，系统流程待验收；由用户手动开启 |
| 通话与音频 | 未实现 |

目前仅接受已核实的 USB `2ca3:4006`、AT 接口 2 / bulk `0x84`、`0x03`，以及 `QDC507` / `QDC507GLEFM21` 型号固件组合。外壳型号相同不代表其他固件或接口布局一定兼容。支持范围详见 [验证记录](VALIDATION.md)。

## 构建

需要 Apple Silicon Mac、Xcode 或具备 macOS SDK 的 Swift 工具链。包声明 macOS 13+、Swift 5.9+；目前实测环境为 macOS 26.5 / Swift 6.3.3，最低系统版本尚未实测。

```sh
git clone https://github.com/popomars/LTEModemCompact.git
cd LTEModemCompact
swift test
zsh scripts/build-app.sh
```

产物为 `dist/LTEModemCompact.app` 和独立诊断工具 `dist/ModemDiagnostics`。默认本地 ad-hoc 签名，仓库不含已公证安装包。可用 `LTE_MODEM_COMPACT_SIGN_IDENTITY` 指定自己的签名身份；签名不等于公证。

## 使用

1. 连接已配置 ECM 的模块，并按 macOS 提示允许 USB 配件。这个应用不替新模块自动改写 ECM、ADB 或固件。
2. 正常退出占用同一模块 AT 接口的其他客户端；同一时间只连接一只支持的模块。
3. 打开应用，从菜单栏天线图标选择“短信与网卡状态…”。应用默认不弹主窗口、不占 Dock。
4. 输入号码与内容，检查段数并确认发送。模块接受后显示“已提交给模块 · 送达未确认”，需要实际收件确认才能算送达。
5. 关闭窗口后仍接收短信；菜单栏退出会停止短信后台，但不影响系统 ECM 网卡。

通知和登录启动在应用设置中手动启用。网络界面上的本地 IP 只代表 USB 本地链路，不能证明 4G 互联网可用。应用不改变 Wi-Fi、VPN、默认出口、APN 或 IMS。

## 短信行为

- 按 SIM 归档；读取前后及发送前核对 SIM，阻止换卡后沿用旧线路发送。
- 当前 SIM 的记录默认单独显示，可查看其他 SIM 和归属未核实的历史。
- 模块已有短信无法可靠推断原 SIM 时，标记为“原 SIM 归属未核实”，不提供快捷回复；首次导入不弹通知。
- 超时、断线、崩溃或部分分段成功均不自动重发；不自动删除模块短信。
- UCS2 文本发送最多 10 段，接收支持 GSM7、UCS2 和长短信拼接。暂不发送 emoji 等补充平面字符。不支持的二进制/编码保留原始 PDU，不显示为文本。
- 约每 4 秒轮询一次，另加设备响应时间；读取模块当前接收存储区，读取可能改变模块的未读标记。

## 数据与兼容性

短信保存在本机，目录权限 `0700`、文件 `0600`；没有应用层额外加密或云同步。完整边界见 [隐私与数据](docs/PRIVACY.md)。

项目早期名为 Native Modem。为保留已有数据、偏好和应用身份，更名后继续使用 `live.lepus.NativeModem` bundle ID 和 `~/Library/Application Support/NativeModem/` 数据目录。这是兼容性保留，不是额外组件；不要同时运行新旧应用。

## 文档

- [使用与故障排查](docs/USAGE.md)
- [架构与协议边界](docs/ARCHITECTURE.md)
- [隐私与数据](docs/PRIVACY.md)
- [开发与贡献](CONTRIBUTING.md)
- [验证记录](VALIDATION.md) / [路线图](ROADMAP.md)

本仓库只包含本项目代码、测试与文档，不包含 DJ4Hub、MaVo、4G-Connect 的源码、后端或音频运行文件，也不依赖这些项目才能构建。构建产物、真实设备日志、短信数据库和本机历史原型不进入版本控制。
