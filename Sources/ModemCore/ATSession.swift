import Foundation
import NativeUSB

public struct USBDevice: Sendable {
    public let registryID: UInt64
    public let location: UInt32
    public static func inventory() throws -> [USBDevice] {
        var items = [NMDevice](repeating: NMDevice(), count: 32)
        let count = nm_devices(&items, items.count)
        guard count >= 0, count <= items.count else { throw ModemError.message("无法可靠枚举 USB AT 接口") }
        return items.prefix(Int(count)).map { USBDevice(registryID: $0.registry_id, location: $0.location) }
    }
}

public protocol ATByteChannel: AnyObject {
    func write(_ bytes: [UInt8]) throws
    func read(timeout: UInt32) throws -> [UInt8]
}

final class USBChannel: ATByteChannel {
    private let handle: OpaquePointer
    init(device: USBDevice) throws {
        var error = [CChar](repeating: 0, count: 256)
        guard let handle = nm_open(device.registryID, &error, error.count) else { throw ModemError.message(String(cString: error)) }
        self.handle = handle
    }
    deinit { nm_close(handle) }
    func write(_ bytes: [UInt8]) throws {
        guard bytes.withUnsafeBytes({ nm_write(handle, $0.baseAddress, UInt32(bytes.count), 2000) }) == 0 else { throw ModemError.message("USB 写入失败；操作结果可能未知") }
    }
    func read(timeout: UInt32) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = nm_read(handle, &bytes, UInt32(bytes.count), timeout)
        guard count >= 0 else { throw ModemError.message(String(format: "USB 读取失败 (0x%08x)", nm_last_error(handle))) }
        return Array(bytes.prefix(Int(count)))
    }
}

public final class ATSession {
    private let channel: ATByteChannel
    public init(channel: ATByteChannel) { self.channel = channel }
    convenience init(device: USBDevice) throws { self.init(channel: try USBChannel(device: device)) }
    public func synchronize() throws {
        // Discard only bytes predating this session. No previously queued write is retried.
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline { if try channel.read(timeout: 100).isEmpty { return } }
        throw ModemError.message("AT 通道持续忙碌，请稍后重试")
    }
    func cancelPendingInput() throws {
        // ESC cancels a CMGS text-entry prompt left by a disconnected previous owner.
        // Never use Ctrl-Z for recovery: that could submit an unknown old payload.
        try channel.write([27])
        try synchronize()
    }
    public func command(_ command: String, timeout: TimeInterval = 8) throws -> String {
        guard !command.contains("\r"), !command.contains("\n") else { throw ModemError.message("AT 命令格式无效") }
        try channel.write(Array((command + "\r").utf8))
        return try response(timeout: timeout, prompt: false)
    }
    public func submit(_ part: SMSSubmit) throws -> String {
        try channel.write(Array("AT+CMGS=\(part.tpduLength)\r".utf8))
        _ = try response(timeout: 8, prompt: true)
        try channel.write(Array(part.hex.utf8) + [26])
        let response = try response(timeout: 60, prompt: false)
        guard response.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("+CMGS:") }) else { throw ModemError.message("模块未返回短信提交编号；结果未知，不会自动重发") }
        return response
    }
    private func response(timeout: TimeInterval, prompt: Bool) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer: [UInt8] = []
        while Date() < deadline {
            buffer += try channel.read(timeout: 200)
            guard buffer.count < 512 * 1024 else { throw ModemError.message("AT 响应超过容量限制") }
            let text = String(decoding: buffer, as: UTF8.self)
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.contains(where: { $0 == "ERROR" || $0.hasPrefix("+CMS ERROR:") || $0.hasPrefix("+CME ERROR:") }) {
                // Error lines may include private message echoes elsewhere; expose just the status.
                throw ModemError.message(lines.first(where: { $0 == "ERROR" || $0.hasPrefix("+CMS ERROR:") || $0.hasPrefix("+CME ERROR:") }) ?? "模块拒绝命令")
            }
            if prompt && text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(">") { return text }
            if !prompt && lines.contains("OK") { return text }
        }
        throw ModemError.message("AT 响应超时；操作结果未知，不会自动重发")
    }
}
