import AppKit
import UserNotifications

extension Controller {
    func refreshNotifications() async {
        guard !demo else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        notificationNeedsPermission = settings.authorizationStatus == .notDetermined
        switch settings.authorizationStatus {
        case .notDetermined: notificationStatus = "短信通知尚未开启"
        case .denied: notificationStatus = "系统已关闭通知，请到系统设置中允许"
        case .authorized, .provisional:
            if !notificationEnabled { notificationStatus = "短信通知已在应用内暂停" }
            else if settings.alertSetting != .enabled || settings.alertStyle == .none {
                notificationStatus = "通知权限已允许；横幅未开启，请检查系统通知设置"
            } else { notificationStatus = "新短信通知已开启" }
        @unknown default: notificationStatus = "通知权限状态未知，请检查系统设置"
        }
    }
    func setNotificationsEnabled(_ enabled: Bool) {
        guard !demo else { return }
        notificationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "smsNotificationsEnabled")
        if enabled { retryNotifications() } else { Task { await refreshNotifications() } }
    }
    func setNotificationSound(_ enabled: Bool) {
        guard !demo else { return }
        notificationSound = enabled
        UserDefaults.standard.set(enabled, forKey: "smsNotificationSound")
    }
    func retryNotifications() {
        guard !demo, !notificationBusy else { return }
        notificationBusy = true; notificationNotice = ""
        notificationEnabled = true
        UserDefaults.standard.set(true, forKey: "smsNotificationsEnabled")
        Task {
            defer { notificationBusy = false }
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                if !granted { notificationNotice = "请在系统设置 → 通知 → LTEModemCompact 中打开“允许通知”。" }
            } catch { notificationNotice = "无法申请通知权限：\(error.localizedDescription)" }
            await refreshNotifications()
        }
    }
    func openNotificationSettings() {
        guard !demo else { return }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        if !NSWorkspace.shared.open(url) {
            notificationNotice = "请手动打开系统设置 → 通知 → LTEModemCompact。"
        }
    }
    func testNotification() {
        guard !demo, !notificationBusy, notificationEnabled else { return }
        notificationBusy = true; notificationNotice = ""
        Task {
            defer { notificationBusy = false }
            await refreshNotifications()
            guard notificationsAuthorized else { notificationNotice = "请先允许通知，再测试。"; return }
            let content = UNMutableNotificationContent()
            content.title = "短信通知测试"
            content.body = "提醒已就绪。这是本机测试，不会发送短信或产生费用。"
            content.sound = notificationSound ? .default : nil
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "local-notification-test", content: content, trigger: nil))
                notificationNotice = "测试通知已提交给 macOS；若未显示，请检查专注模式及系统通知的横幅设置。"
            } catch { notificationNotice = "测试通知提交失败：\(error.localizedDescription)" }
        }
    }
}
