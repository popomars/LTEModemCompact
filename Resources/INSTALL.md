LTEModemCompact 0.3.0 — Apple Silicon Mac

安装
1. 将 LTEModemCompact.app 拖到 Applications（应用程序）。
2. 从“应用程序”打开 LTEModemCompact。
3. 点击菜单栏天线图标，选择“短信与网卡状态…”。本应用默认不显示 Dock 图标。
4. 连接已配置 ECM 的受支持模块，并按系统提示允许 USB 配件。

升级
先正常退出旧版本再替换应用。新旧版本共用应用身份与本地数据位置，不要同时运行。
替换应用不删除短信记录。为了兼容早期版本，数据目录仍使用：
~/Library/Application Support/NativeModem/

支持范围
Apple Silicon（arm64），应用声明 macOS 13 或更高版本。
目前实测 macOS 26.5；其他系统版本仍待验收。
当前版本提供独立网卡页面、Wi-Fi/4G 优先级切换和短信，语音尚未实现。
切换时仅对调 Wi-Fi 与当前模块的位置，系统可能要求管理员授权；可以撤销上次切换。
其他更靠前的网络服务或 Clash/VPN 仍可能影响实际出口；4G 可能消耗套餐流量。
同一时间仅连接一只受支持模块，其他占用 AT 接口的客户端应先退出。

签名
此预览安装包使用本地 ad-hoc 签名，尚无 Developer ID 分发签名和 Apple 公证。
系统可能阻止首次打开。安装包不会修改系统安全设置，也不包含任何绕过命令。

数据
应用首次启动不会自动注册登录项或请求通知；可在设置中手动开启。
本地短信未做应用层额外加密。退出应用不影响系统 ECM 网卡，卸载应用不删除历史。
安装包不包含短信、SIM 标识、真实号码、设备日志或第三方运行文件。

项目与使用文档
https://github.com/popomars/LTEModemCompact
