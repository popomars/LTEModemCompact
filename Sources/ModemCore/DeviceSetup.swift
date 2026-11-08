import Foundation

public struct DeviceSetupReport: Sendable {
    public let token: UUID
    public let model: String
    public let firmware: String
    public let usbMode: Int
    public let canEnableECM: Bool
    public let canRestore: Bool
    public let detail: String
}
struct SetupIdentity: Codable, Equatable {
    let deviceHash: String
    let model: String
    let firmware: String
    let usbConfiguration: [Int]
    let usbMode: Int
}
private struct SetupBackup: Codable {
    let version: Int
    let before: SetupIdentity
    let createdAt: Date
}
private struct SetupPlan {
    let token: UUID
    let device: USBDevice
    let identity: SetupIdentity
}

// A narrow configuration transaction, not a firmware flasher. Access is serialized
// by ModemEngine and the existing per-user process lock. Never imports a backup.
final class DeviceSetup {
    private let directory: URL
    private let discover: () throws -> [USBDevice]
    private let connect: (USBDevice) throws -> ATSession
    private var plan: SetupPlan?
    init(directory: URL, discover: @escaping () throws -> [USBDevice], connect: @escaping (USBDevice) throws -> ATSession) {
        self.directory = directory.appendingPathComponent("device-setup", isDirectory: true)
        self.discover = discover; self.connect = connect
    }
    static func payload(_ response: String, command: String) throws -> String {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != command && $0 != "OK" }
        guard lines.count == 1 else { throw ModemError.message("设备响应有歧义；未允许写入") }
        return lines[0]
    }
    static func qcfg(_ response: String, name: String) throws -> [Int] {
        let line = try payload(response, command: "AT+QCFG=\"\(name)\"")
        let fields = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.first == "+QCFG: \"\(name)\"" else { throw ModemError.message("配置响应格式不匹配；未允许写入") }
        return try fields.dropFirst().map { field in
            let hex = field.lowercased().hasPrefix("0x")
            guard let value = Int(hex ? String(field.dropFirst(2)) : field, radix: hex ? 16 : 10), value >= 0 else {
                throw ModemError.message("配置数值不匹配；未允许写入")
            }
            return value
        }
    }
    static func validate(_ identity: SetupIdentity) throws {
        guard identity.model == "QDC507", identity.firmware == "QDC507GLEFM21" else {
            throw ModemError.message("内部型号或固件不在已验证范围；不会修改配置或刷固件")
        }
        let c = identity.usbConfiguration
        guard c.count == 9, Array(c.prefix(7)) == [0x2ca3, 0x4006, 1, 1, 1, 1, 1],
              (0...1).contains(c[7]), c[8] == 0, (0...1).contains(identity.usbMode) else {
            throw ModemError.message("USB 组合或网络模式与已验证配置不同；不会覆盖未知配置")
        }
        guard identity.deviceHash.count == 64, identity.deviceHash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw ModemError.message("设备身份无效；不会写入")
        }
    }
    private func singleDevice() throws -> USBDevice {
        let devices = try discover()
        guard devices.count == 1 else { throw ModemError.message("初始化需要恰好一只受支持模块；请检查连接，其他型号/接口不自动探测") }
        return devices[0]
    }
    private func identify(_ channel: ATSession) throws -> SetupIdentity {
        try channel.synchronize()
        _ = try channel.command("AT")
        let model = try Self.payload(channel.command("AT+CGMM"), command: "AT+CGMM")
        let firmware = try Self.payload(channel.command("AT+CGMR"), command: "AT+CGMR")
        guard model == "QDC507", firmware == "QDC507GLEFM21" else { throw ModemError.message("内部型号或固件不在已验证范围；不会修改配置或刷固件") }
        let rawIdentity = try Self.payload(channel.command("AT+CGSN"), command: "AT+CGSN")
        guard rawIdentity.utf8.count == 15, rawIdentity.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw ModemError.message("无法可靠识别设备，不能建立可恢复的配置备份")
        }
        let c = try Self.qcfg(channel.command("AT+QCFG=\"usbcfg\""), name: "usbcfg")
        let n = try Self.qcfg(channel.command("AT+QCFG=\"usbnet\""), name: "usbnet")
        guard n.count == 1 else { throw ModemError.message("网络模式响应有歧义；未允许写入") }
        let identity = SetupIdentity(deviceHash: MessageStore.digest(rawIdentity), model: model, firmware: firmware, usbConfiguration: c, usbMode: n[0])
        try Self.validate(identity)
        return identity
    }
    private func backupURL(_ identity: SetupIdentity) -> URL { directory.appendingPathComponent(identity.deviceHash + ".json") }
    private func loadBackup(for identity: SetupIdentity) throws -> SetupBackup? {
        let url = backupURL(identity)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let backup = try JSONDecoder().decode(SetupBackup.self, from: Data(contentsOf: url))
        try Self.validate(backup.before)
        guard backup.version == 1, backup.before.deviceHash == identity.deviceHash,
              backup.before.model == identity.model, backup.before.firmware == identity.firmware,
              backup.before.usbConfiguration == identity.usbConfiguration, backup.before.usbMode == 0 else {
            throw ModemError.message("本机备份与当前设备配置不匹配；不会覆盖备份或修改设备")
        }
        return backup
    }
    func inspect() throws -> DeviceSetupReport {
        plan = nil
        let device = try singleDevice()
        let channel = try connect(device)
        let identity = try identify(channel)
        let backup = try loadBackup(for: identity)
        let token = UUID()
        plan = SetupPlan(token: token, device: device, identity: identity)
        return DeviceSetupReport(token: token, model: identity.model, firmware: identity.firmware, usbMode: identity.usbMode,
                                 canEnableECM: identity.usbMode == 0, canRestore: identity.usbMode == 1 && backup != nil,
                                 detail: identity.usbMode == 1 ? "已配置 ECM，无需重复初始化；联网仍取决于 SIM、信号和运营商。" : "可初始化为 macOS 原生 ECM 网卡；不需要刷固件。")
    }
    func apply(token: UUID, restoring: Bool) throws -> String {
        guard let plan, plan.token == token else { throw ModemError.message("检查结果已过期，请重新检查设备") }
        self.plan = nil // A plan is one-use, including uncertain failures. Never retry automatically.
        let device = try singleDevice()
        guard device.registryID == plan.device.registryID, device.location == plan.device.location else {
            throw ModemError.message("设备已拔插或换口，请重新检查；未写入")
        }
        let channel = try connect(device)
        let current = try identify(channel)
        guard current == plan.identity else { throw ModemError.message("设备或配置在检查后发生变化；未写入") }
        let target: Int
        if restoring {
            guard current.usbMode == 1, let backup = try loadBackup(for: current) else { throw ModemError.message("没有可恢复到当前设备的原配置") }
            target = backup.before.usbMode
        } else {
            guard current.usbMode == 0 else { throw ModemError.message("设备已经是 ECM，无需重复初始化") }
            // Re-read before saving; never overwrite a corrupt or conflicting backup.
            if try loadBackup(for: current) == nil {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                let data = try JSONEncoder().encode(SetupBackup(version: 1, before: current, createdAt: Date()))
                let url = backupURL(current)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.synchronize()
                guard try Data(contentsOf: url) == data else { throw ModemError.message("备份回读失败；未写入设备") }
            }
            target = 1
        }
        // Persistent setters start only after the complete backup is safely on disk.
        do {
            _ = try channel.command("AT+QCFG=\"usbnet\",\(target)")
            let mode = try Self.qcfg(channel.command("AT+QCFG=\"usbnet\""), name: "usbnet")
            let composition = try Self.qcfg(channel.command("AT+QCFG=\"usbcfg\""), name: "usbcfg")
            guard mode == [target], composition == current.usbConfiguration else {
                throw ModemError.message("写入后回读不一致")
            }
        } catch {
            throw ModemError.message("配置写入或回读未确认，已停止且不自动重试；原配置备份保留。请重新检查实际状态后决定恢复。")
        }
        // USB may disappear before an OK; do not equate the acknowledgement with recovery.
        do {
            _ = try channel.command("AT+CFUN=1,1", timeout: 3)
            return "配置回读正确，已请求模块重启。等待重新枚举后点击“检查设备”复查；必要时断电重插。"
        } catch {
            return "配置回读正确，但重启响应未确认（可能已掉线重启）。不重复发送；等待模块恢复后重新检查，必要时断电重插。"
        }
    }
    func invalidate() { plan = nil }
}
