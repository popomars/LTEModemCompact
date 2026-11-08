import XCTest
@testable import NetworkCore

final class ServiceOrderTests: XCTestCase {
    func testOnlyWiFiAndModulePositionsChange() throws {
        let before = ["ethernet", "wifi", "vpn-a", "module", "vpn-b"]
        let after = try ServiceOrderPlan.prefer("module", over: "wifi", in: before)
        XCTAssertEqual(after, ["ethernet", "module", "vpn-a", "wifi", "vpn-b"])
        XCTAssertEqual(try ServiceOrderPlan.prefer("wifi", over: "module", in: after), before)
        XCTAssertEqual(try ServiceOrderPlan.prefer("wifi", over: "module", in: before), before)
    }
    func testMissingAndAmbiguousServicesAreRejected() {
        for order in [["wifi"], ["wifi", "module", "module"]] {
            XCTAssertThrowsError(try ServiceOrderPlan.prefer("module", over: "wifi", in: order))
        }
        XCTAssertThrowsError(try ServiceOrderPlan.prefer("wifi", over: "wifi", in: ["wifi"]))
    }
    func testRestoreNeverOverwritesExternalChanges() throws {
        let before = ["wifi", "module", "vpn"], after = ["module", "wifi", "vpn"]
        XCTAssertEqual(try ServiceOrderPlan.restore(current: after, after: after, before: before, sameLocation: true), before)
        XCTAssertThrowsError(try ServiceOrderPlan.restore(current: after + ["new-service"], after: after, before: before, sameLocation: true))
        XCTAssertThrowsError(try ServiceOrderPlan.restore(current: after, after: after, before: before, sameLocation: false))
        XCTAssertThrowsError(try ServiceOrderPlan.restore(current: after, after: after, before: ["wifi", "module"], sameLocation: true))
    }
    func testSelfAssignedAddressIsNotReadyForSwitching() {
        XCTAssertFalse(NetworkLink(name: "en1", addresses: ["169.254.1.2"], router: nil, active: true).hasAddress)
        XCTAssertTrue(NetworkLink(name: "en1", addresses: ["192.0.2.2"], router: nil, active: true).hasAddress)
    }
}
