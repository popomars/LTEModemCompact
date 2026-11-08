import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let controller: Controller
    private var item: NSStatusItem?
    private var statusLine: NSMenuItem?
    private var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var terminating = false
    init(controller: Controller) { self.controller = controller }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        item.button?.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: "LTEModemCompact")
        let menu = NSMenu()
        let status = NSMenuItem(title: "正在启动后台…", action: nil, keyEquivalent: "")
        menu.addItem(status); statusLine = status
        menu.addItem(.separator())
        let show = NSMenuItem(title: "短信与网卡状态…", action: #selector(openWindow), keyEquivalent: "")
        show.target = self; menu.addItem(show)
        let network = NSMenuItem(title: "网卡与上网优先级…", action: #selector(openNetwork), keyEquivalent: "")
        network.target = self; menu.addItem(network)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 LTEModemCompact", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu
        controller.onStatus = { [weak self] value in self?.statusLine?.title = value; self?.item?.button?.toolTip = value }
        controller.onOpen = { [weak self] in self?.openWindow() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.controller.releaseForSleep() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.controller.sleeping = false } })
        controller.start()
        if controller.demo || ProcessInfo.processInfo.arguments.contains("--show") { openWindow() }
    }
    private func installMainMenu() {
        // A programmatic AppKit agent needs an Edit menu for the standard text
        // responder shortcuts, including pasting a number or message into SwiftUI.
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quit = NSMenuItem(title: "退出 LTEModemCompact", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu; main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await controller.refreshNotifications() }
    }
    @objc private func openNetwork() { controller.section = .network; openWindow() }
    @objc func openWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "LTEModemCompact"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WorkspaceView(controller: controller))
            window.delegate = self; window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        Task { await controller.stop(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
