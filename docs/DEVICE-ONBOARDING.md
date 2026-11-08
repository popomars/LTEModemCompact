# 安装入口与插入启动

## 已安装过应用的 Mac

先将完整应用拖入系统或用户的 Applications 文件夹，再打开设置。插入行为默认为关闭，可选择先询问或自动后台启动。通过 SMAppService 注册随包的 LaunchAgent；等待系统允许时显示 requiresApproval 状态，可到系统登录项设置批准。关闭写入停用偏好并注销服务，失败时明确报错；停用偏好仍阻止助手再开主程序。

助手封装在应用内，使用 `com.apple.iokit.matching` 的 LaunchEvents 匹配 IOUSBHostDevice `2ca3:4006`，启动后先注册 XPC 流处理器，消费事件以免反复被 launchd 拉起。收到事件后重新核实硬件 ID，去除重复枚举，主应用已经运行则不再启动。去重记录包含本次系统启动 UUID 和临时 IORegistry ID，不是设备序列号。无事件或无有效工作时约 12 秒退出；询问窗口等待用户选择时保留。助手不打开 AT，不读短信，不联网，不自动安装代码。

“登录自动启动”和“插入时启动”互相独立。若两项都开启且主应用已在运行，插入不会再弹询问。若希望仅插入时启动，关闭登录自动启动。移动/删除应用前先关闭插入启动；更新时退出主应用并替换完整 bundle，必要时在新版设置中重新注册。

当前完成构建、策略测试与嵌套签名检查，SMAppService 用户批准、launchd 真实插入事件及提示窗口仍待实机验收。ad-hoc 签名不等于 Apple 公证。

## 全新 Mac

当前 ECM 网卡没有主机侧安装程序，不能主动要求系统从 GitHub 下载。可行的候选方案是在原 ECM/AT/ADB 组合后追加只读 USB 存储功能，向 Finder 呈现一个安装入口盘。生成的 ISO 仅含三个静态文件：

- `START HERE.html`：离线中文说明与 GitHub Releases 按钮，无 JavaScript 或外部资源。
- `Download LTEModemCompact.webloc`：固定公开仓库发布页。
- `README.txt`：中英文入口说明。

无需预装程序即可读取入口盘；点击下载仍需要互联网能访问 GitHub，安装仍需用户操作并遵守 Gatekeeper。不能保证 Finder 自动开窗或网页自动弹出。

## 当前设备证据与临时试验

当前连接设备的只读检查显示内核 3.18.44、原 USB 组合 `diag,serial,ecm,ffs`、`CONFIG_USB_F_MASS_STORAGE=y`，并有可用的 mass-storage LUN file/ro 属性。未改固件，不能把能力存在等同于接口共存已成功。另一只型号仍需单独验证。

镜像可由 `python3 scripts/build-device-portal.py` 构建，已在 Mac 只读挂载核实静态内容。试验脚本只能在对应模块上执行，预检包括内核、USB 组合、VID/PID、LUN 空闲、镜像 SHA-256。只有显式 apply 参数才更改临时 sysfs 接口；不写系统分区或开机配置。脚本必须由独立 nohup/setsid 进程启动，以便 USB 掉线后仍在 90 秒恢复原组合。试验会短暂断开网卡和短信，失败时可能需要断电重插。主应用不会代用户执行该脚本。

试验仅使用 /tmp；断电后入口不会保留。模块系统分区当前只读，尚未找到并验证可用的用户启动钩子。持久安装需要另外设计可回退的启动集成；先通过临时共存试验，再审查具体写入与恢复步骤，不能直接宣称“任意 Mac 插上即有入口”。

## 参考

- [Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [Apple 后台组件迁移与 BundleProgram](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- 本机 macOS `xpc_events(3)` 手册：USB 匹配事件、LaunchEvents 与流消费要求。
