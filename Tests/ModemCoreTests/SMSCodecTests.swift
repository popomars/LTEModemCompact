import XCTest
@testable import ModemCore

final class SMSCodecTests: XCTestCase {
    // Fixtures are assembled from protocol fields, not taken from private device messages.
    func deliver(_ payload: [UInt8], dcs: UInt8 = 8, header: Bool = false, length: UInt8? = nil) -> String {
        let prefix: [UInt8] = [0, header ? 0x40 : 0, 11, 0x81, 0x21, 0x20, 0x55, 0x05, 0x01, 0xF4, 0, dcs,
                               0x62, 0x11, 0x80, 0x21, 0x43, 0x65, 0x23, length ?? UInt8(payload.count)]
        return (prefix + payload).map { String(format: "%02X", $0) }.joined()
    }
    func pack(_ codes: [UInt8], offset: Int = 0, prefix: [UInt8] = []) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: (offset + codes.count * 7 + 7) / 8)
        for (i, value) in prefix.enumerated() { data[i] = value }
        for (i, code) in codes.enumerated() {
            for bit in 0..<7 where code & (1 << bit) != 0 {
                let position = offset + i * 7 + bit
                data[position / 8] |= 1 << (position % 8)
            }
        }
        return data
    }
    func testDomesticAndInternationalNumberTypes() throws {
        let local = try SMSCodec.bytes(SMSCodec.encode(to: "12025550104", text: "中")[0].hex)
        let international = try SMSCodec.bytes(SMSCodec.encode(to: "+12025550104", text: "中")[0].hex)
        XCTAssertEqual(local[4], 0x81)
        XCTAssertEqual(international[4], 0x91)
        XCTAssertEqual(local[3], 11)
        XCTAssertEqual(Array(local.suffix(2)), [0x4E, 0x2D])
        XCTAssertEqual(local[10], 0xF4)
    }
    func testSegmentationBoundariesAndTPDULength() throws {
        XCTAssertEqual(try SMSCodec.encode(to: "10010", text: String(repeating: "中", count: 70)).count, 1)
        let parts = try SMSCodec.encode(to: "10010", text: String(repeating: "中", count: 71), reference: 42)
        XCTAssertEqual(parts.count, 2)
        for (i, part) in parts.enumerated() {
            let bytes = try SMSCodec.bytes(part.hex)
            XCTAssertEqual(part.tpduLength, bytes.count - 1)
            XCTAssertEqual(bytes[1], 0x41)
            XCTAssertEqual(Array(bytes[11..<17]), [5, 0, 3, 42, 2, UInt8(i + 1)])
        }
        XCTAssertThrowsError(try SMSCodec.encode(to: "10010", text: String(repeating: "中", count: 671)))
    }
    func testInvalidInputsRejectCommandInjectionAndEmoji() {
        for number in ["+", "12\rATD110;", "12 34", "+12+34", "１２３", String(repeating: "1", count: 21)] {
            XCTAssertThrowsError(try SMSCodec.encode(to: number, text: "hello"))
        }
        XCTAssertThrowsError(try SMSCodec.encode(to: "10010", text: ""))
        XCTAssertThrowsError(try SMSCodec.encode(to: "10010", text: "你好😀"))
    }
    func testUCS2DeliverAndTimeZone() throws {
        let decoded = try SMSCodec.decode(deliver([0x4F, 0x60, 0x59, 0x7D]))
        XCTAssertEqual(decoded.text, "你好")
        XCTAssertEqual(decoded.sender, "12025550104")
        XCTAssertEqual(decoded.timestamp.ISO8601Format(), "2026-11-08T04:34:56Z")
    }
    func testGSM7Extensions() throws {
        let codes: [UInt8] = [72, 101, 108, 108, 111, 32, 27, 101, 27, 20, 27, 40, 27, 41]
        let decoded = try SMSCodec.decode(deliver(pack(codes), dcs: 0, length: UInt8(codes.count)))
        XCTAssertEqual(decoded.text, "Hello €^{}")
    }
    func testGSM7UserHeaderPadding() throws {
        let header: [UInt8] = [5, 0, 3, 17, 2, 1]
        let decoded = try SMSCodec.decode(deliver(pack([65,66,67], offset: 49, prefix: header), dcs: 0, header: true, length: 10))
        XCTAssertEqual(decoded.text, "ABC")
        XCTAssertEqual(decoded.reference, 17)
        XCTAssertEqual(decoded.sequence, 1)
    }
    func testSixteenBitConcatenationHeader() throws {
        let decoded = try SMSCodec.decode(deliver([6,8,4,0x12,0x34,2,2,0,66], header: true))
        XCTAssertEqual(decoded.text, "B")
        XCTAssertEqual(decoded.reference, 0x1234)
        XCTAssertEqual(decoded.sequence, 2)
    }
    func testMalformedAndUnsupportedPDUsNeverTrap() throws {
        let valid = deliver([0x4F,0x60])
        let bytes = try SMSCodec.bytes(valid)
        for count in 1..<bytes.count {
            XCTAssertThrowsError(try SMSCodec.decode(bytes.prefix(count).map { String(format:"%02X", $0) }.joined()))
        }
        for raw in ["", "1", "ZZ", deliver([1], dcs: 8), deliver([0,1], dcs: 4), deliver([9,0], header: true), deliver([5,0,3,1,0,0], header: true)] {
            XCTAssertThrowsError(try SMSCodec.decode(raw))
        }
    }
}
