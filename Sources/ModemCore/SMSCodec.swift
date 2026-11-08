import Foundation

public enum ModemError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct SMSPart: Codable, Equatable, Sendable {
    public let sender: String
    public let text: String
    public let timestamp: Date
    public let reference: Int?
    public let total: Int
    public let sequence: Int
    public let raw: String
}

public struct SMSSubmit: Sendable {
    public let hex: String
    public let tpduLength: Int
}

// 3GPP TS 23.040 TPDU framing and TS 23.038 default alphabet.
// This is a local implementation; no external SMS library is linked.
public enum SMSCodec {
    private static let alphabet: [Character] = Array("@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\u{001B}ÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà")
    private static let extended: [UInt8: String] = [10:"\u{000C}",20:"^",40:"{",41:"}",47:"\\",60:"[",61:"~",62:"]",64:"|",101:"€"]

    public static func bytes(_ hex: String) throws -> [UInt8] {
        guard !hex.isEmpty, hex.count % 2 == 0, hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw ModemError.message("短信 PDU 格式无效") }
        let chars = Array(hex.utf8)
        func digit(_ n: UInt8) -> UInt8 { n <= 57 ? n - 48 : (n & 0xdf) - 55 }
        return stride(from: 0, to: chars.count, by: 2).map { digit(chars[$0]) * 16 + digit(chars[$0 + 1]) }
    }
    private static func hex(_ data: [UInt8]) -> String { data.map { String(format: "%02X", $0) }.joined() }

    public static func normalizedNumber(_ number: String) throws -> String {
        let value = number.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("+") ? String(value.dropFirst()) : value
        guard (1...20).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }) else { throw ModemError.message("号码仅支持数字和开头的 +，最长 20 位") }
        return value
    }

    public static func encode(to number: String, text: String, reference: UInt8 = UInt8.random(in: 0...255)) throws -> [SMSSubmit] {
        let number = try normalizedNumber(number)
        guard !text.isEmpty else { throw ModemError.message("短信正文不能为空") }
        guard text.unicodeScalars.allSatisfy({ $0.value <= 0xffff }) else { throw ModemError.message("当前短信发送支持中英文 BMP 字符；请移除 emoji 等补充平面字符") }
        let international = number.hasPrefix("+")
        let digits = Array((international ? String(number.dropFirst()) : number).utf8).map { $0 - 48 }
        var address: [UInt8] = []
        for i in stride(from: 0, to: digits.count, by: 2) { address.append(digits[i] | ((i + 1 < digits.count ? digits[i + 1] : 15) << 4)) }
        // UCS2 is deliberate: no national-language shift-table guessing for Chinese.
        let units = Array(text.utf16)
        let limit = units.count <= 70 ? 70 : 67
        let total = (units.count + limit - 1) / limit
        guard total <= 10 else { throw ModemError.message("单次最多发送 10 段短信") }
        return stride(from: 0, to: units.count, by: limit).enumerated().map { index, offset in
            var payload: [UInt8] = total > 1 ? [5, 0, 3, reference, UInt8(total), UInt8(index + 1)] : []
            for unit in units[offset..<min(offset + limit, units.count)] { payload += [UInt8(unit >> 8), UInt8(unit & 255)] }
            let pdu: [UInt8] = [0, total > 1 ? 0x41 : 0x01, 0, UInt8(digits.count), international ? 0x91 : 0x81] + address + [0, 8, UInt8(payload.count)] + payload
            return SMSSubmit(hex: hex(pdu), tpduLength: pdu.count - 1)
        }
    }

    private static func gsm7(_ data: [UInt8], count: Int, bitOffset: Int = 0) throws -> String {
        guard count >= 0, bitOffset >= 0, bitOffset + count * 7 <= data.count * 8 else { throw ModemError.message("GSM7 短信长度不完整") }
        var result = "", escape = false
        for index in 0..<count {
            let bit = bitOffset + index * 7
            let byte = bit / 8, shift = bit % 8
            var value = UInt16(data[byte]) >> shift
            if shift > 1 && byte + 1 < data.count { value |= UInt16(data[byte + 1]) << (8 - shift) }
            let code = UInt8(value & 127)
            if escape { result += extended[code] ?? "�"; escape = false }
            else if code == 27 { escape = true }
            else { result.append(alphabet[Int(code)]) }
        }
        if escape { result += "�" }
        return result
    }

    public static func decode(_ raw: String) throws -> SMSPart {
        let data = try bytes(raw)
        var cursor = 0
        func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, cursor + count <= data.count else { throw ModemError.message("短信 PDU 被截断") }
            defer { cursor += count }; return Array(data[cursor..<cursor + count])
        }
        func byte() throws -> UInt8 { try take(1)[0] }
        let smscLength = Int(try byte()); _ = try take(smscLength)
        let first = try byte()
        guard first & 3 == 0 else { throw ModemError.message("当前接收只解码 SMS-DELIVER") }
        let length = Int(try byte()), type = try byte()
        let address = try take((length + 1) / 2)
        let sender: String
        if type & 0x70 == 0x50 { sender = try gsm7(address, count: length * 4 / 7) }
        else {
            let nibbles = address.flatMap { [$0 & 15, $0 >> 4] }.prefix(length)
            let symbols = Array("0123456789*#abc")
            guard nibbles.allSatisfy({ $0 < 15 }) else { throw ModemError.message("短信发件地址无效") }
            sender = (type & 0x70 == 0x10 ? "+" : "") + String(nibbles.map { symbols[Int($0)] })
        }
        _ = try byte() // TP-PID
        let dcs = try byte()
        let stamp = try take(7)
        func decimal(_ b: UInt8) -> Int { Int(b & 15) * 10 + Int(b >> 4) }
        let quarterHours = Int(stamp[6] & 7) * 10 + Int(stamp[6] >> 4)
        let zoneSeconds = quarterHours * 900 * (stamp[6] & 8 == 0 ? 1 : -1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: zoneSeconds) ?? TimeZone(secondsFromGMT: 0)!
        let year = decimal(stamp[0])
        let timestamp = calendar.date(from: DateComponents(year: year >= 90 ? 1900 + year : 2000 + year, month: decimal(stamp[1]), day: decimal(stamp[2]), hour: decimal(stamp[3]), minute: decimal(stamp[4]), second: decimal(stamp[5]))) ?? Date(timeIntervalSince1970: 0)
        let udl = Int(try byte())
        let coding: Int
        if dcs & 0xc0 == 0 {
            guard dcs & 0x20 == 0 else { throw ModemError.message("暂不解码压缩短信") }
            coding = Int((dcs >> 2) & 3)
        } else if dcs & 0xf0 == 0xe0 { coding = 2 }
        else if dcs & 0xf0 == 0xc0 || dcs & 0xf0 == 0xd0 { coding = 0 }
        else if dcs & 0xf0 == 0xf0 { coding = dcs & 4 == 0 ? 0 : 1 }
        else { throw ModemError.message("暂不解码此短信字符集") }
        let payload = try take(coding == 0 ? (udl * 7 + 7) / 8 : udl)
        var headerSize = 0, reference: Int?, total = 1, sequence = 1
        if first & 0x40 != 0 {
            guard let h = payload.first else { throw ModemError.message("短信缺少用户数据头") }
            headerSize = Int(h) + 1
            guard headerSize <= payload.count else { throw ModemError.message("短信用户数据头被截断") }
            var i = 1
            while i < headerSize {
                guard i + 2 <= headerSize else { throw ModemError.message("短信扩展头不完整") }
                let kind = payload[i], size = Int(payload[i + 1]); i += 2
                guard i + size <= headerSize else { throw ModemError.message("短信扩展头越界") }
                if kind == 0 && size == 3 { reference = Int(payload[i]); total = Int(payload[i+1]); sequence = Int(payload[i+2]) }
                if kind == 8 && size == 4 { reference = Int(payload[i]) * 256 + Int(payload[i+1]); total = Int(payload[i+2]); sequence = Int(payload[i+3]) }
                // National shift tables need an explicit decoder, never silently use GSM defaults.
                if kind == 0x24 || kind == 0x25 { throw ModemError.message("暂不解码国家语言转换表") }
                i += size
            }
        }
        guard total > 0, sequence > 0, sequence <= total else { throw ModemError.message("长短信分段编号无效") }
        let body: String
        switch coding {
        case 0:
            let skipped = (headerSize * 8 + 6) / 7
            body = try gsm7(payload, count: udl - skipped, bitOffset: skipped * 7)
        case 2:
            let content = Array(payload.dropFirst(headerSize))
            guard content.count % 2 == 0 else { throw ModemError.message("UCS2 短信长度无效") }
            let units = stride(from: 0, to: content.count, by: 2).map { UInt16(content[$0]) * 256 + UInt16(content[$0+1]) }
            body = String(decoding: units, as: UTF16.self)
        default: throw ModemError.message("二进制短信已保留，暂不作为文本显示")
        }
        return SMSPart(sender: sender, text: body, timestamp: timestamp, reference: reference, total: total, sequence: sequence, raw: raw.uppercased())
    }
}
