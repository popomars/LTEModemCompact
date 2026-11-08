import XCTest
@testable import ModemCore

// A stateful modem double tests the whole engine, including its durable send journal.
// No USB, real SIM or network is accessed by these tests.
// SIM values are synthetic digits, not identifiers read from hardware.
final class VirtualModem: ATByteChannel {
    var sim = "9999000000000000000"
    var model = "QDC507"
    var firmware = "QDC507GLEFM21"
    var imei = String(repeating: "1", count: 15)
    var usbMode = 0
    var usbConfig = "0x2CA3,0x4006,1,1,1,1,1,0,0"
    var failSetter = false
    var failReboot = false
    var beforeSetter: (() throws -> Void)?
    var pdus: [String] = []
    var commands: [String] = []
    var swapDuringList = false
    var failSIM = false
    var payloads = 0
    var disconnectAfterPayload = false
    private var replies: [[UInt8]] = []
    func write(_ bytes: [UInt8]) throws {
        if bytes == [27] { return }
        if bytes.last == 26 {
            payloads += 1
            if disconnectAfterPayload { throw ModemError.message("模拟提交后断线") }
            replies.append(Array("\r\n+CMGS: 7\r\nOK\r\n".utf8)); return
        }
        let command = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        commands.append(command)
        var response = ""
        switch command {
        case "AT": break
        case "AT+CGMM": response = model
        case "AT+CGMR": response = firmware
        case "AT+CGSN": response = imei
        case "AT+QCFG=\"usbcfg\"": response = "+QCFG: \"usbcfg\", \(usbConfig)"
        case "AT+QCFG=\"usbnet\"": response = "+QCFG: \"usbnet\", \(usbMode)"
        case "AT+QCFG=\"usbnet\",0", "AT+QCFG=\"usbnet\",1":
            try beforeSetter?()
            usbMode = command.hasSuffix("1") ? 1 : 0
            if failSetter { throw ModemError.message("uncertain write") }
        case "AT+CFUN=1,1":
            if failReboot { throw ModemError.message("USB disappeared") }
        case "AT+CPIN?":
            if failSIM { throw ModemError.message("SIM 已移除") }
            response = "+CPIN: READY"
        case "AT+QCCID": response = "+QCCID: \(sim)"
        case "AT+CEREG?": response = "+CEREG: 0,1"
        case "AT+COPS?": response = "+COPS: 0,0,\"TEST\",7"
        case "AT+CMGF=0": break
        case "AT+CPMS?": response = "+CPMS: \"ME\",0,255,\"ME\",0,255,\"ME\",0,255"
        case "AT+CMGL=4":
            if swapDuringList { sim = "9999000000000000099" }
            response = pdus.enumerated().map { "+CMGL: \($0.offset),0,,1\r\n\($0.element)" }.joined(separator: "\r\n")
        default:
            if command.hasPrefix("AT+CMGS=") { replies.append(Array("\r\n> ".utf8)); return }
            throw ModemError.message("测试遇到未预期命令")
        }
        replies.append(Array(("\r\n" + response + "\r\nOK\r\n").utf8))
    }
    func read(timeout: UInt32) throws -> [UInt8] { replies.isEmpty ? [] : replies.removeFirst() }
}

final class EngineTests: XCTestCase {
    func directory() -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("LTEModemCompact-engine-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }; return path
    }
    func make(_ modem: VirtualModem, directory: URL) throws -> ModemEngine {
        try ModemEngine(directory: directory, discover: { [USBDevice(registryID: 1, location: 1)] }, connect: { _ in ATSession(channel: modem) })
    }
    func testSupportedDevicePollAndReplugReopen() async throws {
        let modem = VirtualModem(), path = directory()
        let engine = try make(modem, directory: path)
        let first = await engine.poll()
        XCTAssertTrue(first.canSend); XCTAssertTrue(first.registered)
        await engine.disconnect()
        let second = await engine.poll()
        XCTAssertEqual(first.sim, second.sim)
        XCTAssertEqual(modem.commands.filter { $0 == "AT+CGMM" }.count, 2)
        XCTAssertFalse(modem.commands.contains { $0.contains("QCFG=") || $0.contains("CMGD") || $0.hasPrefix("ATD") })
    }
    func testHotSIMSwapCannotUseStaleReplyLine() async throws {
        let modem = VirtualModem(), path = directory()
        let engine = try make(modem, directory: path)
        let first = await engine.poll()
        modem.sim = "9999000000000000001"
        do { _ = try await engine.send(to: "10010", text: "A", expectedSIM: first.sim!); XCTFail("SIM swap must block") }
        catch { XCTAssertTrue(error.localizedDescription.contains("SIM 已更换")) }
        XCTAssertEqual(modem.payloads, 0)
        XCTAssertFalse(modem.commands.contains { $0.hasPrefix("AT+CMGS=") })
    }
    func testSubmissionPersistsAcknowledgementWithoutDeliveryClaim() async throws {
        let modem = VirtualModem(), path = directory()
        let engine = try make(modem, directory: path)
        let first = await engine.poll()
        let sent = try await engine.send(to: "10010", text: "A", expectedSIM: first.sim!)
        XCTAssertEqual(sent.messages.first?.state, .submitted)
        XCTAssertEqual(sent.messages.first?.submittedParts, 1)
        XCTAssertEqual(modem.payloads, 1)
        XCTAssertTrue(sent.messages.first!.state.title.contains("送达未确认"))
    }
    func testSubmissionUncertaintyIsDurableAndNeverRetriedOnPoll() async throws {
        let modem = VirtualModem(), path = directory()
        let engine = try make(modem, directory: path)
        let first = await engine.poll()
        modem.disconnectAfterPayload = true
        do { _ = try await engine.send(to: "10010", text: "A", expectedSIM: first.sim!); XCTFail("Expected disconnect") } catch {}
        _ = await engine.poll()
        XCTAssertEqual(modem.payloads, 1)
        let saved = try MessageStore(directory: path)
        XCTAssertEqual(saved.messages.first?.state, .uncertain)
    }
    func testUnknownFirmwareDoesNotSetSMSMode() async throws {
        let modem = VirtualModem(); modem.firmware = "OTHER"
        let engine = try make(modem, directory: directory())
        let state = await engine.poll()
        XCTAssertFalse(state.canSend)
        XCTAssertFalse(modem.commands.contains("AT+CMGF=0"))
    }
    func testMultipleDevicesOpenNoInterfaces() async throws {
        let modem = VirtualModem()
        let engine = try ModemEngine(directory: directory(), discover: { [USBDevice(registryID: 1, location: 1),USBDevice(registryID: 2, location: 2)] }, connect: { _ in XCTFail("Must not open ambiguous device"); return ATSession(channel: modem) })
        let state = await engine.poll()
        XCTAssertFalse(state.canSend)
        XCTAssertTrue(state.status.contains("多个模块"))
    }
    func testNewIncomingMessageOnceAcrossPollingAndReplug() async throws {
        let modem = VirtualModem(), path = directory()
        let engine = try make(modem, directory: path)
        _ = await engine.poll()
        let fields: [UInt8] = [0,0,4,0x81,0x21,0x43,0,8,0x62,0x11,0x80,0x21,0x43,0,0x23,2,0x4F,0x60]
        modem.pdus = [fields.map { String(format:"%02X", $0) }.joined()]
        let received = await engine.poll()
        XCTAssertEqual(received.newMessages.count, 1)
        XCTAssertEqual(received.newMessages.first?.text, "你")
        let repeatPoll = await engine.poll()
        XCTAssertTrue(repeatPoll.newMessages.isEmpty)
        await engine.disconnect()
        let replug = await engine.poll()
        XCTAssertTrue(replug.newMessages.isEmpty)
        XCTAssertEqual(replug.messages.count, 1)
    }
    func testCardSwapDuringReadNeverArchivesToWrongSIM() async throws {
        let modem = VirtualModem(), path = directory()
        modem.swapDuringList = true
        let engine = try make(modem, directory: path)
        let state = await engine.poll()
        XCTAssertNil(state.sim)
        XCTAssertTrue(state.status.contains("读取期间 SIM 已更换"))
        XCTAssertTrue(state.messages.isEmpty)
    }
    func testSIMRemovalBeforeSendDisablesStaleLine() async throws {
        let modem = VirtualModem(), path = directory()
        let engine = try make(modem, directory: path)
        let state = await engine.poll()
        modem.failSIM = true
        do { _ = try await engine.send(to: "10010", text: "A", expectedSIM: state.sim!); XCTFail("must reject") } catch {}
        let after = await engine.current()
        XCTAssertFalse(after.canSend)
        XCTAssertFalse(after.registered)
        XCTAssertEqual(modem.payloads, 0)
    }

}
