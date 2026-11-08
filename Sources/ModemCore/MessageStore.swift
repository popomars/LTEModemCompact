import Foundation
import CryptoKit

public enum SendState: String, Codable, Sendable {
    case received, preparing, submitting, submitted, uncertain, failed
    public var title: String {
        switch self {
        case .received: return "已接收"
        case .preparing: return "准备发送"
        case .submitting: return "正在提交"
        case .submitted: return "已提交给模块 · 送达未确认"
        case .uncertain: return "结果未知 · 不会自动重发"
        case .failed: return "发送前失败"
        }
    }
}
public struct Message: Codable, Identifiable, Sendable {
    public let id: String
    public let sim: String
    public let peer: String
    public var text: String
    public let date: Date
    public var state: SendState
    public var submittedParts: Int
    public var totalParts: Int
    public var detail: String
    public var parts: [SMSPart]
    public var complete: Bool { state != .received || parts.count == totalParts }
}
private struct Archive: Codable {
    var version = 1
    var messages: [Message] = []
    var rawBySIM: [String: [String]] = [:]
    var initializedSIMs: Set<String> = []
}

public final class MessageStore {
    private let url: URL
    private var archive: Archive
    public static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        url = directory.appendingPathComponent("messages-v1.json")
        if FileManager.default.fileExists(atPath: url.path) {
            archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version == 1 else { throw ModemError.message("短信数据库版本不支持；原文件未覆盖") }
        } else { archive = Archive() }
        // A crash between device submission and the next durable save must not resend.
        var recovered = false
        for i in archive.messages.indices where archive.messages[i].state == .submitting || archive.messages[i].state == .preparing {
            archive.messages[i].state = .uncertain
            archive.messages[i].detail = "上次运行在发送完成前结束；请向收件人核实"
            recovered = true
        }
        if recovered { try save() }
    }
    public var messages: [Message] { archive.messages.sorted { $0.date > $1.date } }
    public func message(id: String) -> Message? { archive.messages.first { $0.id == id } }
    private func save() throws {
        let data = try JSONEncoder().encode(archive)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".messages-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw ModemError.message("无法创建私有短信存储文件") }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stream = try FileHandle(forWritingTo: temporary)
        do { try stream.write(contentsOf: data); try stream.synchronize(); try stream.close() }
        catch { try? stream.close(); throw error }
        guard rename(temporary.path, url.path) == 0 else { throw ModemError.message("短信存储原子替换失败") }
    }
    public func begin(to peer: String, text: String, sim: String, count: Int) throws -> String {
        let id = UUID().uuidString
        let previous = archive
        archive.messages.append(Message(id: id, sim: sim, peer: peer, text: text, date: Date(), state: .preparing, submittedParts: 0, totalParts: count, detail: "", parts: []))
        do { try save() } catch { archive = previous; throw error }; return id
    }
    public func update(id: String, state: SendState, submitted: Int, detail: String = "") throws {
        guard let i = archive.messages.firstIndex(where: { $0.id == id }) else { throw ModemError.message("未找到发送记录") }
        let previous = archive
        archive.messages[i].state = state; archive.messages[i].submittedParts = submitted
        archive.messages[i].detail = detail
        do { try save() } catch { archive = previous; throw error }
    }
    // Archive the entire PDU before decoding; unsupported text is never deleted from the device.
    // Initial import is quiet. Subsequent complete incoming messages produce notifications.
    public func ingest(_ pdus: [String], sim: String, historicalOwnerUnknown: Bool = false) throws -> [Message] {
        let initial = !archive.initializedSIMs.contains(sim)
        var known = Set(archive.rawBySIM[sim] ?? [])
        let fresh = pdus.filter { !known.contains($0.uppercased()) }
        guard initial || !fresh.isEmpty else { return [] }
        let previous = archive
        var completed: [String] = []
        for raw in fresh where !known.contains(raw.uppercased()) {
            let raw = raw.uppercased()
            known.insert(raw)
            // ME can retain another card's messages across a SIM swap. First-import
            // ownership is unknown; never offer a reply routed through the new SIM.
            let owner = initial && historicalOwnerUnknown ? "unassigned" : sim
            if historicalOwnerUnknown && archive.messages.contains(where: { $0.parts.contains(where: { $0.raw == raw }) }) { continue }
            guard let part = try? SMSCodec.decode(raw) else { continue }
            let group = archive.messages.firstIndex {
                $0.sim == owner && $0.state == .received && $0.peer == part.sender &&
                part.reference != nil && $0.parts.first?.reference == part.reference && $0.totalParts == part.total &&
                abs($0.date.timeIntervalSince(part.timestamp)) < 3600 &&
                !$0.parts.contains(where: { $0.sequence == part.sequence }) && !$0.complete
            }
            let index: Int
            if let group { index = group; archive.messages[index].parts.append(part) }
            else {
                index = archive.messages.count
                archive.messages.append(Message(id: Self.digest(owner + ":" + raw), sim: owner, peer: part.sender, text: "", date: part.timestamp, state: .received, submittedParts: 0, totalParts: part.total, detail: owner == "unassigned" ? "模块已有短信，原 SIM 归属未核实；不提供快捷回复" : "", parts: [part]))
            }
            archive.messages[index].parts.sort { $0.sequence < $1.sequence }
            archive.messages[index].text = archive.messages[index].parts.map(\.text).joined()
            if archive.messages[index].complete { completed.append(archive.messages[index].id) }
        }
        archive.rawBySIM[sim] = known.sorted()
        archive.initializedSIMs.insert(sim)
        do { try save() }
        catch { archive = previous; throw error }
        return initial ? [] : completed.compactMap { message(id: $0) }
    }
}
