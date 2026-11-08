import Foundation

public enum DeviceProbe {
    // Explicit opt-in command-line diagnostic. Queries only; does not select SMS mode,
    // read SMS, change network configuration, reboot or prepare audio.
    public static func run() throws -> [String: Any] {
        let devices = try USBDevice.inventory()
        guard devices.count == 1 else { throw ModemError.message("只读诊断需要恰好一只可见的受支持模块；当前 \(devices.count) 只") }
        let channel = try ATSession(device: devices[0])
        try channel.synchronize()
        _ = try channel.command("AT")
        let model = try channel.command("AT+CGMM")
        let firmware = try channel.command("AT+CGMR")
        let pin = try channel.command("AT+CPIN?")
        let registration = try channel.command("AT+CEREG?")
        let usbnet = try channel.command("AT+QCFG=\"usbnet\"")
        return ["supported_model": model.contains("QDC507"), "supported_firmware": firmware.contains("QDC507GLEFM21"),
                "sim_ready": pin.contains("+CPIN: READY"), "lte_registration": registration.components(separatedBy: .newlines).first(where: { $0.hasPrefix("+CEREG:") }) ?? "unknown",
                "ecm_configured": usbnet.contains("\"usbnet\",1"), "network": NetworkStatus.summary(), "queries_only": true]
    }
}
