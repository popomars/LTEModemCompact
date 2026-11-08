import AppKit
import Foundation
import NetworkCore

umask(0o077)
let arguments = ProcessInfo.processInfo.arguments
do {
    if arguments.contains("--inventory") {
        let state = NetworkMonitor.read()
        print("{\"supported_at_interfaces\":\(state.deviceCount),\"opens_usb\":false}")
        exit(0)
    }
    if arguments.contains("--diagnose") {
        let state = NetworkMonitor.read()
        let report: [String: Any] = ["milestone": 1, "status": state.status, "network": state.network, "device_count": state.deviceCount, "has_local_address": state.hasLocalAddress, "opens_usb": false, "sends_at": false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self)); exit(0)
    }
    let demo = arguments.contains("--demo")
    let directory = demo ? FileManager.default.temporaryDirectory.appendingPathComponent("LTEModemCompact-demo-\(ProcessInfo.processInfo.processIdentifier)") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NativeModem", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lock = open(directory.appendingPathComponent("agent.lock").path, O_CREAT | O_RDWR, 0o600)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
        fputs("LTEModemCompact 后台已运行或无法获得私有存储锁。\n", stderr); exit(1)
    }
    try MainActor.assumeIsolated {
        let application = NSApplication.shared
        let controller = try Controller(directory: directory, demo: demo)
        let delegate = AppDelegate(controller: controller)
        application.delegate = delegate
        application.run()
    }
    close(lock)
} catch {
    // No SMS body, ICCID, USB serial or full AT response is printed.
    fputs("LTEModemCompact: \(error.localizedDescription)\n", stderr)
    exit(1)
}
