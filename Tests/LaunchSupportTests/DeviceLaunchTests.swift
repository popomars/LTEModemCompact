import XCTest
@testable import LaunchSupport

final class DeviceLaunchTests: XCTestCase {
    func testUnknownModeFailsClosed() {
        XCTAssertEqual(DeviceLaunchPolicy.mode(nil), .off)
        XCTAssertEqual(DeviceLaunchPolicy.mode("unknown"), .off)
        XCTAssertEqual(DeviceLaunchPolicy.mode("ask"), .ask)
    }
    func testDisabledUnsupportedRunningAndDuplicateNeverLaunch() {
        func check(_ mode: DeviceLaunchMode = .ask, supported: Bool = true, running: Bool = false, last: String? = nil) -> Bool {
            DeviceLaunchPolicy.shouldHandle(mode: mode, supported: supported, alreadyRunning: running, registryID: "boot:1", lastID: last)
        }
        XCTAssertTrue(check()); XCTAssertTrue(check(.automatic))
        XCTAssertFalse(check(.off)); XCTAssertFalse(check(supported: false))
        XCTAssertFalse(check(running: true)); XCTAssertFalse(check(last: "boot:1"))
        XCTAssertTrue(check(last: "old-boot:1"))
    }
    func testHostResolutionUsesEmbeddedBundleOnly() {
        let host = URL(fileURLWithPath: "/Applications/LTEModemCompact.app")
        let helper = host.appendingPathComponent("Contents/Library/LoginItems/LTEModemCompact USB Launcher.app")
        XCTAssertEqual(DeviceLaunchPolicy.hostApplication(helper: helper), host)
        XCTAssertNil(DeviceLaunchPolicy.hostApplication(helper: URL(fileURLWithPath: "/tmp/USBLauncher.app")))
        XCTAssertNil(DeviceLaunchPolicy.hostApplication(helper: URL(fileURLWithPath: "/tmp/Contents/Library/LoginItems/LTEModemCompact USB Launcher.app")))
    }
}
