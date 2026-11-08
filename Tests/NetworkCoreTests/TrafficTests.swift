import XCTest
@testable import NetworkCore

final class TrafficTests: XCTestCase {
    private func counter(_ received: UInt64, _ sent: UInt64 = 0, name: String = "en-test", generation: String = "1") -> TrafficCounter {
        TrafficCounter(name: name, generation: generation, received: received, sent: sent)
    }
    func testBaselineThen64BitDeltasAndRates() {
        var accumulator = TrafficAccumulator()
        accumulator.sample([counter(5_000_000_000, 7_000_000_000)], uptime: 10)
        XCTAssertEqual(accumulator.snapshot.totalReceived, 0)
        accumulator.sample([counter(5_000_001_000, 7_000_000_500)], uptime: 15)
        XCTAssertEqual(accumulator.snapshot.sessionReceived, 1_000)
        XCTAssertEqual(accumulator.snapshot.totalSent, 500)
        XCTAssertEqual(accumulator.snapshot.receiveRate, 200)
        XCTAssertEqual(accumulator.snapshot.sendRate, 100)
    }
    func testDisconnectResetAndRecreatedInterfaceNeverSpike() {
        var a = TrafficAccumulator()
        a.sample([counter(100)], uptime: 1)
        a.sample([counter(150)], uptime: 6)
        a.sample([], uptime: 11)
        a.sample([counter(9_000)], uptime: 16)
        a.sample([counter(9_500, generation: "2")], uptime: 21)
        a.sample([counter(10, generation: "2")], uptime: 26)
        XCTAssertEqual(a.snapshot.totalReceived, 50)
        XCTAssertEqual(a.snapshot.receiveRate, 0)
        a.sample([counter(30, generation: "2")], uptime: 31)
        XCTAssertEqual(a.snapshot.totalReceived, 70)
    }
    func testSleepLongGapAndClockRollbackDoNotImportUnobservedTraffic() {
        var a = TrafficAccumulator()
        a.sample([counter(10)], uptime: 10)
        a.sample([counter(20)], uptime: 15)
        a.suspend()
        a.sample([counter(20_000)], uptime: 20)
        a.sample([counter(30_000)], uptime: 100)
        a.sample([counter(40_000)], uptime: 90)
        XCTAssertEqual(a.snapshot.totalReceived, 10)
        a.sample([counter(40_100)], uptime: 95)
        XCTAssertEqual(a.snapshot.totalReceived, 110)
    }
    func testMultipleInterfacesCountOnceAndResetClearsBaseline() {
        var a = TrafficAccumulator(totalReceived: 200)
        a.sample([counter(10), counter(20, name: "en-other")], uptime: 1)
        a.sample([counter(30), counter(30), counter(50, name: "en-other")], uptime: 6)
        XCTAssertEqual(a.snapshot.totalReceived, 250)
        XCTAssertEqual(a.snapshot.sessionReceived, 50)
        let since = Date(timeIntervalSince1970: 123)
        a.reset(now: since)
        a.sample([counter(60)], uptime: 11)
        XCTAssertEqual(a.snapshot.totalReceived, 0)
        XCTAssertEqual(a.snapshot.since, since)
    }
    func testPersistenceRetainsTotalsButNotOldBaselineAndUsesPrivateFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tracker = TrafficTracker(directory: dir)
        _ = await tracker.sample([counter(50)], uptime: 1)
        _ = await tracker.sample([counter(250, 100)], uptime: 6)
        let reopened = TrafficTracker(directory: dir)
        let snapshot = await reopened.sample([counter(5_000, 1_000)], uptime: 11)
        XCTAssertEqual(snapshot.totalReceived, 200)
        XCTAssertEqual(snapshot.totalSent, 100)
        XCTAssertEqual(snapshot.sessionReceived, 0)
        XCTAssertTrue(snapshot.notice.isEmpty)
        let permissions = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("network-traffic-v1.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let cleared = try await reopened.reset()
        XCTAssertEqual(cleared.totalReceived, 0)
        let final = await TrafficTracker(directory: dir).sample([], uptime: 12)
        XCTAssertEqual(final.totalSent, 0)
    }
    func testCorruptArchiveIsPreservedUntilExplicitReset() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("network-traffic-v1.json")
        let original = Data("unreadable".utf8)
        try original.write(to: url)
        let tracker = TrafficTracker(directory: dir)
        let snapshot = await tracker.sample([counter(100)], uptime: 1)
        XCTAssertFalse(snapshot.notice.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
        _ = try await tracker.reset()
        XCTAssertNotEqual(try Data(contentsOf: url), original)
    }
    func testUnavailableInterfaceReturnsNoCounters() {
        XCTAssertTrue(TrafficMonitor.read(names: ["no-such-interface"]).isEmpty)
    }
}
