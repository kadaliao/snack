import Foundation
import SnackKit
import UserNotifications

/// Local notifications: a reminder each day at the chosen time, for a week ahead,
/// and a last call at night while a streak is about to end. They are all made
/// again whenever the day changes how it stands, so a day whose goal is met has
/// no reminder left.
enum Reminders {
    /// The night's last call for a streak.
    static let lastCall = 22 * 60

    /// Asks for permission the first time; says whether reminders may be shown.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    static func reschedule(streak: Streak, xpToday: Int, goal: Int, now: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.remind) else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let at = defaults.integer(forKey: Prefs.remindAt)
        let today = Day(now)
        for offset in 0..<7 {
            let day = today.adding(offset)
            if offset == 0 && xpToday >= goal { continue }
            let body: String = switch offset {
            case 0 where streak.isAtRisk: "🔥 连胜 \(streak.count) 天，今天刷一节就能续上"
            case 0 where xpToday == 0: "今天还没刷。两分钟一节，现在就来？"
            case 0: "今天的目标还差 \(goal - xpToday) XP，大约 \((goal - xpToday + 99) / 100) 节"
            case 1 where streak.isDoneToday: "🔥 连胜 \(streak.count) 天，今天接着来"
            default: idle[(offset + today.day) % idle.count]
            }
            await add(center, id: "daily-\(day)", day: day, minutes: at, body: body, now: now)
        }
        // The last call: tonight while the streak waits for today, and tomorrow
        // night, in case the app is not opened tomorrow.
        if at < lastCall {
            if streak.isAtRisk {
                let body = streak.freezes > 0
                    ? "🔥 连胜 \(streak.count) 天，今天不刷会用掉一张冻结卡"
                    : "🔥 连胜 \(streak.count) 天今晚就断了，刷一节保住它"
                await add(center, id: "streak-\(today)", day: today, minutes: lastCall, body: body, now: now)
            }
            if streak.isDoneToday {
                await add(center, id: "streak-\(today.adding(1))", day: today.adding(1), minutes: lastCall, body: "🔥 连胜 \(streak.count) 天今晚就断了，刷一节保住它", now: now)
            }
        }
    }

    private static let idle = [
        "两分钟，刷一节卡片零食",
        "有卡片等你复习",
        "趁现在有空，刷一节？",
        "今天的卡片零食还没吃",
    ]

    private static func add(_ center: UNUserNotificationCenter, id: String, day: Day, minutes: Int, body: String, now: Date) async {
        // Days are Gregorian, whatever calendar the phone shows.
        var when = DateComponents()
        when.calendar = Calendar(identifier: .gregorian)
        when.timeZone = .current
        when.year = day.year
        when.month = day.month
        when.day = day.day
        when.hour = minutes / 60
        when.minute = minutes % 60
        guard let date = when.date, date > now else { return }
        let content = UNMutableNotificationContent()
        content.title = "卡片零食"
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
