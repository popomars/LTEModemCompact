import XCTest
@testable import ModemCore

final class ScriptedChannel: ATByteChannel {
    var writes: [[UInt8]] = []
    var chunks: [[UInt8]]
    init(_ chunks: [String]) { self.chunks = chunks.map { Array($0.utf8) } }
    func write(_ bytes: [UInt8]) throws { writes.append(bytes) }
    func read(timeout: UInt32) throws -> [UInt8] {
        guard !chunks.isEmpty else { throw ModemError.message("模拟 USB 断开") }
        return chunks.removeFirst()
    }
}

final class StoreAndATTests: XCTestCase {
    func temp() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LTEModemCompact-tests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    func fixture(_ payload: [UInt8], header: Bool = false, second: UInt8 = 0) -> String {
        let fields: [UInt8] = [0,header ? 0x40 : 0,4,0x81,0x21,0x43,0,8,0x62,0x11,0x80,0x21,0x43,second,0x23,UInt8(payload.count)]
        return (fields + payload).map { String(format:"%02X", $0) }.joined()
    }
    func testMultipartOutOfOrderPersistsDeduplicatesAndIsolatesSIM() throws {
        let directory = try temp()
        var store = try MessageStore(directory: directory)
        XCTAssertTrue(try store.ingest([], sim: "sim-a").isEmpty)
        let second = fixture([5,0,3,1,2,2,0,66], header: true)
        let first = fixture([5,0,3,1,2,1,0,65], header: true)
        XCTAssertTrue(try store.ingest([second], sim: "sim-a").isEmpty)
        store = try MessageStore(directory: directory)
        let notifications = try store.ingest([first, second], sim: "sim-a")
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.text, "AB")
        XCTAssertEqual(store.messages.count, 1)
        XCTAssertTrue(try store.ingest([first,second], sim: "sim-a").isEmpty)
        XCTAssertTrue(try store.ingest([first,second], sim: "sim-b").isEmpty)
        XCTAssertEqual(store.messages.count, 2)
        let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("messages-v1.json").path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }
    func testCrashRecoveryNeverMarksInterruptedSendSuccessful() throws {
        let directory = try temp()
        let store = try MessageStore(directory: directory)
        let id = try store.begin(to: "10010", text: "test", sim: "a", count: 2)
        try store.update(id: id, state: .submitting, submitted: 1)
        let recovered = try MessageStore(directory: directory)
        XCTAssertEqual(recovered.message(id: id)?.state, .uncertain)
        XCTAssertEqual(recovered.message(id: id)?.submittedParts, 1)
    }
    func testCorruptDatabaseIsNotOverwritten() throws {
        let directory = try temp()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("messages-v1.json")
        try Data("corrupt".utf8).write(to: file)
        XCTAssertThrowsError(try MessageStore(directory: directory))
        XCTAssertEqual(try String(contentsOf: file), "corrupt")
    }
    func testPDUListToleratesInterleavedURCs() {
        let response = "\r\n+CMGL: 1,0,,3\r\n+CMTI: \"ME\",2\r\n001122\r\n+CMGL: 2,1,,3\r\n334455\r\nOK\r\n"
        XCTAssertEqual(ModemEngine.pduList(response), ["001122","334455"])
    }
    func testCommandHandlesSplitTerminalAndNoPrematureOKSubstring() throws {
        let channel = ScriptedChannel(["\r\n+COPS: \"TOKYO\"\r\nO", "K\r\n"])
        let response = try ATSession(channel: channel).command("AT+COPS?")
        XCTAssertTrue(response.contains("TOKYO"))
        XCTAssertEqual(channel.writes, [Array("AT+COPS?\r".utf8)])
    }
    func testPromptThenSubmitAndOneCtrlZ() throws {
        let channel = ScriptedChannel(["\r\n>", "\r\n+CMGS: 23\r\nOK\r\n"])
        let part = try SMSCodec.encode(to: "10010", text: "A")[0]
        _ = try ATSession(channel: channel).submit(part)
        XCTAssertEqual(channel.writes.count, 2)
        XCTAssertEqual(channel.writes[1], Array(part.hex.utf8) + [26])
    }
    func testSubmissionDisconnectAndMissingReferenceNeverRetry() throws {
        let part = try SMSCodec.encode(to: "10010", text: "A")[0]
        for responses in [["\r\n>"], ["\r\n>","\r\nOK\r\n"], ["\r\n+CMS ERROR: 500\r\n"]] {
            let channel = ScriptedChannel(responses)
            XCTAssertThrowsError(try ATSession(channel: channel).submit(part))
            XCTAssertLessThanOrEqual(channel.writes.count, 2)
        }
    }
    func testRecoveryCancelsPromptWithoutSubmittingUnknownPayload() throws {
        final class QuietChannel: ATByteChannel {
            var writes: [[UInt8]] = []
            func write(_ bytes: [UInt8]) throws { writes.append(bytes) }
            func read(timeout: UInt32) throws -> [UInt8] { [] }
        }
        let channel = QuietChannel()
        try ATSession(channel: channel).cancelPendingInput()
        XCTAssertEqual(channel.writes, [[27]])
    }
    func testExistingModuleMessagesNeverAssignedToNewCard() throws {
        let store = try MessageStore(directory: temp())
        let old = fixture([0,65])
        XCTAssertTrue(try store.ingest([old], sim: "card-a", historicalOwnerUnknown: true).isEmpty)
        XCTAssertEqual(store.messages.first?.sim, "unassigned")
        _ = try store.ingest([old], sim: "card-b", historicalOwnerUnknown: true)
        XCTAssertEqual(store.messages.count, 1)
        let fresh = fixture([0,66], second: 1)
        let incoming = try store.ingest([old, fresh], sim: "card-b", historicalOwnerUnknown: true)
        XCTAssertEqual(incoming.count, 1)
        XCTAssertEqual(incoming.first?.sim, "card-b")
    }

}
