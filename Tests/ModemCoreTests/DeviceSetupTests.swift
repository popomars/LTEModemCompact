import XCTest
@testable import ModemCore

final class DeviceSetupTests: XCTestCase {
    func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func make(_ modem: VirtualModem, _ path: URL) -> DeviceSetup {
        DeviceSetup(directory: path, discover: { [USBDevice(registryID: 1, location: 1)] }, connect: { _ in ATSession(channel: modem) })
    }
    func setters(_ modem: VirtualModem) -> [String] {
        modem.commands.filter { $0.hasPrefix("AT+QCFG=\"usbnet\",") || $0 == "AT+CFUN=1,1" }
    }
    func testInspectNeverMutatesAndExistingECMIsNoOp() throws {
        let modem = VirtualModem(); modem.usbMode = 1
        let setup = make(modem, directory())
        let result = try setup.inspect()
        XCTAssertFalse(result.canEnableECM); XCTAssertFalse(result.canRestore)
        XCTAssertThrowsError(try setup.apply(token: result.token, restoring: false))
        XCTAssertTrue(setters(modem).isEmpty)
    }
    func testBackupExistsBeforeWriteAndRestoreKeepsBaseline() throws {
        let modem = VirtualModem(), path = directory(), setup = make(modem, path)
        let backup = path.appendingPathComponent("device-setup/\(MessageStore.digest(modem.imei)).json")
        modem.beforeSetter = {
            let bytes = try Data(contentsOf: backup)
            XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(modem.imei))
            let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        let first = try setup.inspect()
        _ = try setup.apply(token: first.token, restoring: false)
        let baseline = try Data(contentsOf: backup)
        XCTAssertEqual(modem.usbMode, 1)
        XCTAssertThrowsError(try setup.apply(token: first.token, restoring: false))
        let next = try setup.inspect(); XCTAssertTrue(next.canRestore)
        _ = try setup.apply(token: next.token, restoring: true)
        XCTAssertEqual(modem.usbMode, 0)
        _ = try setup.apply(token: setup.inspect().token, restoring: false)
        XCTAssertEqual(try Data(contentsOf: backup), baseline)
        XCTAssertFalse(modem.commands.contains { $0.hasPrefix("AT+QCFG=\"usbcfg\",") })
    }
    func testUnknownFirmwareCompositionOrModeNeverWrites() throws {
        for kind in 0..<3 {
            let modem = VirtualModem(), setup = make(modem, directory())
            if kind == 0 { modem.firmware = "UNKNOWN" }
            if kind == 1 { modem.usbConfig = "0x2CA3,0x4006,1,1,1,1,1,1,1" }
            if kind == 2 { modem.usbMode = 2 }
            XCTAssertThrowsError(try setup.inspect()); XCTAssertTrue(setters(modem).isEmpty)
        }
    }
    func testDeviceSwapAndChangedSettingsRejectStalePlan() throws {
        for kind in 0..<3 {
            let modem = VirtualModem(), path = directory()
            var registry: UInt64 = 1
            let setup = DeviceSetup(directory: path, discover: { [USBDevice(registryID: registry, location: 1)] }, connect: { _ in ATSession(channel: modem) })
            let token = try setup.inspect().token
            if kind == 0 { registry = 2 }
            if kind == 1 { modem.imei = String(repeating: "2", count: 15) }
            if kind == 2 { modem.usbMode = 1 }
            XCTAssertThrowsError(try setup.apply(token: token, restoring: false)); XCTAssertTrue(setters(modem).isEmpty)
        }
    }
    func testUncertainSetterNeverRetriesOrRebootsButAllowsReinspection() throws {
        let modem = VirtualModem(), setup = make(modem, directory())
        let token = try setup.inspect().token; modem.failSetter = true
        XCTAssertThrowsError(try setup.apply(token: token, restoring: false))
        XCTAssertThrowsError(try setup.apply(token: token, restoring: false))
        XCTAssertEqual(setters(modem), ["AT+QCFG=\"usbnet\",1"])
        XCTAssertTrue(try setup.inspect().canRestore)
    }
    func testRebootDisappearanceDoesNotClaimRecovery() throws {
        let modem = VirtualModem(), setup = make(modem, directory()); modem.failReboot = true
        let text = try setup.apply(token: setup.inspect().token, restoring: false)
        XCTAssertTrue(text.contains("重启响应未确认"))
        XCTAssertEqual(setters(modem).filter { $0 == "AT+CFUN=1,1" }.count, 1)
    }
    func testCorruptBackupAndUnwritableDirectoryBlockSetter() throws {
        let modem = VirtualModem(), path = directory(), setup = make(modem, path)
        let token = try setup.inspect().token
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: path.appendingPathComponent("device-setup"))
        XCTAssertThrowsError(try setup.apply(token: token, restoring: false)); XCTAssertTrue(setters(modem).isEmpty)
        try FileManager.default.removeItem(at: path.appendingPathComponent("device-setup"))
        try FileManager.default.createDirectory(at: path.appendingPathComponent("device-setup"), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: path.appendingPathComponent("device-setup/\(MessageStore.digest(modem.imei)).json"))
        XCTAssertThrowsError(try setup.inspect()); XCTAssertTrue(setters(modem).isEmpty)
    }
    func testAmbiguousResponsesRejected() {
        XCTAssertThrowsError(try DeviceSetup.qcfg("+QCFG: \"usbnet\",1\r\nRING\r\nOK", name: "usbnet"))
        XCTAssertThrowsError(try DeviceSetup.qcfg("+QCFG: \"usbnet\",-1\r\nOK", name: "usbnet"))
    }
    func testEngineMaintenancePausesPollingAndSendingThenResumes() async throws {
        let modem = VirtualModem()
        let engine = try ModemEngine(directory: directory(), discover: { [USBDevice(registryID: 1, location: 1)] }, connect: { _ in ATSession(channel: modem) })
        let first = await engine.poll()
        _ = try await engine.inspectDeviceSetup()
        let count = modem.commands.count
        let paused = await engine.poll(); XCTAssertFalse(paused.canSend)
        do { _ = try await engine.send(to: "10010", text: "A", expectedSIM: first.sim!); XCTFail("Must block") } catch {}
        XCTAssertEqual(modem.commands.count, count)
        await engine.endDeviceSetup()
        let resumed = await engine.poll(); XCTAssertTrue(resumed.canSend)
    }
}
