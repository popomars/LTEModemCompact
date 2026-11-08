import Foundation
import ModemCore

// The same engine and private archive as the GUI, with the same process lock.
// Output deliberately excludes SIM identifiers, phone numbers and message bodies.
@main struct ModemDiagnostics {
    static func main() async {
        umask(0o077)
        let args = Array(CommandLine.arguments.dropFirst())
        func option(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NativeModem", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let lock = open(directory.appendingPathComponent("agent.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw ModemError.message("LTEModemCompact 已在运行；请先正常退出再诊断") }
            defer { close(lock) }
            if args == ["--probe"] { try emit(DeviceProbe.run()); return }
            if args == ["--inspect-setup"] {
                let engine = try ModemEngine(directory: directory)
                let report = try await engine.inspectDeviceSetup()
                try emit(["model": report.model, "firmware": report.firmware, "ecm_configured": report.usbMode == 1,
                          "can_initialize": report.canEnableECM, "can_restore": report.canRestore, "queries_only": true])
                await engine.endDeviceSetup()
                return
            }
            let allowed: Set<String> = ["--poll-count", "--send-to", "--text-file", "--expected-reply-file"]
            guard args.count % 2 == 0, stride(from: 0, to: args.count, by: 2).allSatisfy({ allowed.contains(args[$0]) }), let count = Int(option("--poll-count") ?? "1"), (1...60).contains(count) else {
                throw ModemError.message("用法：--probe、--inspect-setup 或 --poll-count 1…60 [--send-to NUMBER --text-file PATH] [--expected-reply-file PATH]")
            }
            guard (option("--send-to") == nil) == (option("--text-file") == nil) else { throw ModemError.message("发送需要同时指定号码和正文文件") }
            let expected = try option("--expected-reply-file").map { try String(contentsOfFile: $0, encoding: .utf8) }
            let engine = try ModemEngine(directory: directory)
            var state = await engine.poll()
            if let number = option("--send-to"), let file = option("--text-file") {
                let body = try String(contentsOfFile: file, encoding: .utf8)
                guard let sim = state.sim else { throw ModemError.message(state.status) }
                state = try await engine.send(to: number, text: body, expectedSIM: sim)
                try emit(["event": "send", "state": "submitted", "delivery_confirmed": false])
            }
            for index in 0..<count {
                if index > 0 { try await Task.sleep(nanoseconds: 4_000_000_000); state = await engine.poll() }
                var report: [String: Any] = ["event": "poll", "index": index, "status": state.status, "sim_ready": state.sim != nil, "registered": state.registered, "stored_messages": state.messages.count, "new_messages": state.newMessages.count]
                if let expected {
                    report["expected_reply_present"] = state.messages.contains { $0.sim == state.sim && $0.state == .received && $0.complete && $0.text == expected }
                }
                try emit(report)
            }
            await engine.disconnect()
            if state.sim == nil { exit(2) }
        } catch {
            fputs("LTEModemCompact: \(error.localizedDescription)\n", stderr); exit(1)
        }
    }
    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self)); fflush(stdout)
    }
}
