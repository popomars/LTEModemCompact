import Foundation
import SystemConfiguration

public struct ModemSnapshot: Sendable {
    public var status: String
    public var sim: String?
    public var carrier: String
    public var registered: Bool
    public var network: String
    public var messages: [Message]
    public var newMessages: [Message]
    public var canSend: Bool { sim != nil }
    public init(status: String, sim: String?, carrier: String, registered: Bool, network: String, messages: [Message], newMessages: [Message]) {
        self.status = status; self.sim = sim; self.carrier = carrier; self.registered = registered
        self.network = network; self.messages = messages; self.newMessages = newMessages
    }
}

public enum NetworkStatus {
    public static func summary() -> String {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return "系统网络信息不可用" }
        let matches = interfaces.filter {
            let name = (SCNetworkInterfaceGetLocalizedDisplayName($0) as String? ?? "").lowercased()
            return name.contains("baiwang") || name.contains("quectel") || name.contains("qdc507")
        }
        guard !matches.isEmpty else { return "等待系统枚举 ECM 网卡" }
        let store = SCDynamicStoreCreate(nil, "LTEModemCompact" as CFString, nil, nil)
        return matches.map { interface in
            let name = SCNetworkInterfaceGetBSDName(interface) as String? ?? "ECM"
            let key = "State:/Network/Interface/\(name)/IPv4" as CFString
            let state = store.flatMap { SCDynamicStoreCopyValue($0, key) as? [String: Any] }
            let addresses = state?["Addresses"] as? [String] ?? []
            return addresses.isEmpty ? "\(name) · 等待 DHCP" : "\(name) · \(addresses.joined(separator: ", ")) · 本地链路已建立"
        }.joined(separator: "\n")
    }
}

public actor ModemEngine {
    private let store: MessageStore
    private let discover: () throws -> [USBDevice]
    private let connect: (USBDevice) throws -> ATSession
    private var session: ATSession?
    private var deviceID: UInt64?
    private var sim: String?
    private var carrier = ""
    private var registered = false
    private var status = "等待插入 IG830 / IG832"
    private var supportedModel = false
    public init(directory: URL) throws {
        store = try MessageStore(directory: directory)
        discover = USBDevice.inventory
        connect = { try ATSession(device: $0) }
    }
    init(directory: URL, discover: @escaping () throws -> [USBDevice], connect: @escaping (USBDevice) throws -> ATSession) throws {
        store = try MessageStore(directory: directory); self.discover = discover; self.connect = connect
    }
    public func disconnect() { session = nil; deviceID = nil; sim = nil; supportedModel = false; registered = false; carrier = "" }
    private func checkIdentity(_ channel: ATSession) throws {
        let model = try channel.command("AT+CGMM")
        let firmware = try channel.command("AT+CGMR")
        guard model.contains("QDC507"), firmware.contains("QDC507GLEFM21") else {
            throw ModemError.message("模块或固件不在已核实范围内；未配置短信模式")
        }
        supportedModel = true
    }
    private func identifySIM(_ channel: ATSession) throws {
        let pin = try channel.command("AT+CPIN?")
        guard pin.contains("+CPIN: READY") else { throw ModemError.message("SIM 未就绪；请检查卡片或在支持的设备上解锁 PIN") }
        let response = try channel.command("AT+QCCID")
        guard let line = response.components(separatedBy: .newlines).first(where: { $0.hasPrefix("+QCCID:") }) else { throw ModemError.message("无法识别 SIM；暂停收发以免混合不同卡片的记录") }
        let id = line.dropFirst(7).trimmingCharacters(in: CharacterSet(charactersIn: " \"\r"))
        guard id.count >= 18, id.count <= 22, id.utf8.allSatisfy({ (48...57).contains($0) || $0 == 70 || $0 == 102 }) else { throw ModemError.message("SIM 标识格式无效") }
        sim = MessageStore.digest(id)
    }
    public static func pduList(_ response: String) -> [String] {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result: [String] = [], expecting = false
        for line in lines {
            if line.hasPrefix("+CMGL:") { expecting = true }
            else if expecting, (try? SMSCodec.bytes(line)) != nil { result.append(line); expecting = false }
            // URCs may interleave between a CMGL header and its PDU.
        }
        return result
    }
    public func poll() -> ModemSnapshot {
        var incoming: [Message] = []
        do {
            let devices = try discover()
            guard devices.count == 1 else {
                disconnect(); status = devices.isEmpty ? "等待插入 IG830 / IG832" : "检测到多个模块；请仅连接一只，避免线路混淆"
                return snapshot(incoming: [])
            }
            let device = devices[0]
            if device.registryID != deviceID || session == nil {
                disconnect()
                let channel = try connect(device)
                try channel.cancelPendingInput()
                try channel.synchronize()
                _ = try channel.command("AT")
                try checkIdentity(channel)
                session = channel; deviceID = device.registryID
            }
            guard let channel = session else { throw ModemError.message("AT 接口不可用") }
            // Read SIM identity every pass, including after hot swap without USB re-enumeration.
            sim = nil
            try identifySIM(channel)
            let registration = try channel.command("AT+CEREG?")
            let registrationLine = registration.components(separatedBy: .newlines).first { $0.hasPrefix("+CEREG:") } ?? ""
            let fields = registrationLine.replacingOccurrences(of: "+CEREG:", with: "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let state = fields.count >= 2 ? fields[1] : fields.first ?? ""
            registered = state == "1" || state == "5"
            // Numeric carrier codes remain useful on firmware returning UCS2 operator names.
            let operatorResponse = try channel.command("AT+COPS?")
            let operatorLine = operatorResponse.components(separatedBy: .newlines).first { $0.hasPrefix("+COPS:") } ?? ""
            let quoted = operatorLine.components(separatedBy: "\"")
            carrier = quoted.count >= 3 ? quoted[1] : "运营商待识别"
            _ = try channel.command("AT+CMGF=0")
            // Read the store used for incoming messages; only change mem1, never
            // the modem's receive destination, SMSC, routing or stored messages.
            let storage = try channel.command("AT+CPMS?")
            let storageLine = storage.components(separatedBy: .newlines).first { $0.hasPrefix("+CPMS:") } ?? ""
            let names = storageLine.components(separatedBy: "\"")
            guard names.count >= 7, ["ME", "SM", "MT"].contains(names[5]) else { throw ModemError.message("无法确认短信接收存储区") }
            let receivingStorage = names[5]
            if names[1] != receivingStorage { _ = try channel.command("AT+CPMS=\"\(receivingStorage)\"") }
            let readingSIM = sim
            let pdus = Self.pduList(try channel.command("AT+CMGL=4", timeout: 25))
            // A card may be replaced while the storage list is being read.
            try identifySIM(channel)
            guard sim == readingSIM else { throw ModemError.message("读取期间 SIM 已更换；暂不归档本次列表") }
            if let sim { incoming = try store.ingest(pdus, sim: sim, historicalOwnerUnknown: receivingStorage != "SM") }
            status = registered ? "模块已就绪 · 短信后台待命" : "SIM 已就绪 · 等待网络注册"
        } catch {
            disconnect(); status = "\(error.localizedDescription) · 将自动重试"
        }
        return snapshot(incoming: incoming)
    }
    private func snapshot(incoming: [Message]) -> ModemSnapshot {
        ModemSnapshot(status: status, sim: sim, carrier: carrier, registered: registered, network: NetworkStatus.summary(), messages: store.messages, newMessages: incoming)
    }
    public func current() -> ModemSnapshot { snapshot(incoming: []) }
    public func replyTarget(id: String) throws -> (String, String) {
        guard let message = store.message(id: id), message.state == .received, message.complete else { throw ModemError.message("未找到可回复的短信") }
        return (message.peer, message.sim)
    }
    public func send(to number: String, text: String, expectedSIM: String) throws -> ModemSnapshot {
        let parts = try SMSCodec.encode(to: number, text: text)
        guard let channel = session, supportedModel else { throw ModemError.message("模块未就绪；没有发送短信") }
        // Recheck the SIM immediately before submission; no routing by a stale UI selection.
        sim = nil
        do { try identifySIM(channel) } catch { disconnect(); throw error }
        guard sim == expectedSIM else { disconnect(); throw ModemError.message("SIM 已更换；没有发送短信，请重新确认线路") }
        _ = try channel.command("AT+CMGF=0")
        let id = try store.begin(to: number, text: text, sim: expectedSIM, count: parts.count)
        var count = 0
        do {
            for part in parts {
                // Durable intent must exist before the first payload reaches the modem.
                try store.update(id: id, state: .submitting, submitted: count)
                _ = try channel.submit(part); count += 1
                try store.update(id: id, state: .submitting, submitted: count)
            }
            try store.update(id: id, state: .submitted, submitted: count)
        } catch {
            disconnect()
            try store.update(id: id, state: .uncertain, submitted: count, detail: "\(error.localizedDescription)；已确认提交 \(count)/\(parts.count) 段")
            throw ModemError.message("发送结果需核实（已确认提交 \(count)/\(parts.count) 段）；不会自动重发")
        }
        return snapshot(incoming: [])
    }
}
