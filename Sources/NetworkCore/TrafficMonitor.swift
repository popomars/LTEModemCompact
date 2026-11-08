import Foundation
import SystemNetworkStats

public struct TrafficCounter: Sendable {
    public let name: String
    public let generation: String
    public let received: UInt64
    public let sent: UInt64
    public init(name: String, generation: String, received: UInt64, sent: UInt64) {
        self.name = name; self.generation = generation; self.received = received; self.sent = sent
    }
}
public enum TrafficMonitor {
    public static func read(names: [String]) -> [TrafficCounter] {
        Set(names).sorted().compactMap { name in
            var value = lte_interface_counters()
            guard lte_read_interface_counters(name, &value) == 0 else { return nil }
            return TrafficCounter(name: name, generation: "\(value.index):\(value.changed_seconds):\(value.changed_microseconds)", received: value.received, sent: value.sent)
        }
    }
}
public struct TrafficSnapshot: Sendable {
    public var sessionReceived: UInt64 = 0
    public var sessionSent: UInt64 = 0
    public var totalReceived: UInt64 = 0
    public var totalSent: UInt64 = 0
    public var receiveRate: Double = 0
    public var sendRate: Double = 0
    public var since: Date = Date()
    public var interfaces: [String] = []
    public var notice = ""
    public init() {}
}
private struct TrafficArchive: Codable {
    var version = 1
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var since = Date()
}
// Counts only consecutive samples while this process is awake. Never infers usage
// during an app-off/sleep gap or imports the kernel's pre-launch lifetime counters.
public struct TrafficAccumulator {
    public private(set) var snapshot = TrafficSnapshot()
    private var previous: [String: TrafficCounter] = [:]
    private var previousTime: TimeInterval?
    public init(totalReceived: UInt64 = 0, totalSent: UInt64 = 0, since: Date = Date()) {
        snapshot.totalReceived = totalReceived; snapshot.totalSent = totalSent; snapshot.since = since
    }
    public mutating func sample(_ counters: [TrafficCounter], uptime: TimeInterval) {
        let current = Dictionary(counters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        snapshot.interfaces = current.keys.sorted()
        snapshot.receiveRate = 0; snapshot.sendRate = 0
        defer { previous = current; previousTime = uptime }
        guard let before = previousTime, uptime > before, uptime - before <= 15 else { return }
        var received: UInt64 = 0, sent: UInt64 = 0
        for (name, counter) in current {
            guard let old = previous[name], old.generation == counter.generation,
                  counter.received >= old.received, counter.sent >= old.sent else { continue }
            received = Self.add(received, counter.received - old.received)
            sent = Self.add(sent, counter.sent - old.sent)
        }
        snapshot.sessionReceived = Self.add(snapshot.sessionReceived, received)
        snapshot.sessionSent = Self.add(snapshot.sessionSent, sent)
        snapshot.totalReceived = Self.add(snapshot.totalReceived, received)
        snapshot.totalSent = Self.add(snapshot.totalSent, sent)
        snapshot.receiveRate = Double(received) / (uptime - before)
        snapshot.sendRate = Double(sent) / (uptime - before)
    }
    private static func add(_ a: UInt64, _ b: UInt64) -> UInt64 {
        let (value, overflow) = a.addingReportingOverflow(b); return overflow ? .max : value
    }
    public mutating func suspend() { previous = [:]; previousTime = nil; snapshot.receiveRate = 0; snapshot.sendRate = 0 }
    public mutating func reset(now: Date = Date()) { self = TrafficAccumulator(since: now) }
}
public actor TrafficTracker {
    private let url: URL
    private var accumulator: TrafficAccumulator
    private var loadError = ""
    public init(directory: URL) {
        url = directory.appendingPathComponent("network-traffic-v1.json")
        accumulator = TrafficAccumulator()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let archive = try JSONDecoder().decode(TrafficArchive.self, from: Data(contentsOf: url))
                guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                accumulator = TrafficAccumulator(totalReceived: archive.received, totalSent: archive.sent, since: archive.since)
            } catch { loadError = "累计记录无法读取；为保护原文件，暂不覆盖。可清零后重新统计。" }
        }
    }
    public func sample(_ counters: [TrafficCounter], uptime: TimeInterval) -> TrafficSnapshot {
        accumulator.sample(counters, uptime: uptime)
        var result = accumulator.snapshot
        if !loadError.isEmpty { result.notice = loadError; return result }
        do { try save() } catch { result.notice = "流量已统计，但累计记录保存失败：\(error.localizedDescription)" }
        return result
    }
    public func suspend() { accumulator.suspend() }
    public func reset() throws -> TrafficSnapshot {
        let old = accumulator
        accumulator.reset()
        do { try save(); loadError = ""; return accumulator.snapshot }
        catch { accumulator = old; throw error }
    }
    private func save() throws {
        let s = accumulator.snapshot
        let archive = TrafficArchive(received: s.totalReceived, sent: s.totalSent, since: s.since)
        let data = try JSONEncoder().encode(archive)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
