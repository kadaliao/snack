import Foundation

/// How the day stands, written by the app for the widget into the App Group both
/// share. The widget works out from it how things will stand later: cards coming
/// due, and at midnight a new day with nothing done yet.
struct WidgetSnapshot: Codable, Equatable {
    static let group = "group.com.kadaliao.snack"
    static let key = "widgetSnapshot"
    /// Opens the app on a new lesson.
    static let lessonURL = URL(string: "snack://lesson")!

    /// The day it was made on, "2026-11-10", where the learner was.
    var day: String
    var streak: Int
    var isDoneToday: Bool
    var freezes: Int
    var xpToday: Int
    var goal: Int
    var dueNow: Int
    /// When each card not yet due comes to count as due, over the next two days.
    var upcoming: [Date]
    var newLeft: Int
    var newPerDay: Int
    var unseen: Int
    var updatedAt: Date

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Saves it; false when it was already so.
    @discardableResult
    func save() -> Bool {
        guard let defaults = UserDefaults(suiteName: Self.group) else { return false }
        var old = Self.load()
        old?.updatedAt = updatedAt
        guard old != self, let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    /// How things stand at `date`.
    struct State: Equatable {
        var streak: Int
        var isDoneToday: Bool
        var isAtRisk: Bool
        var xp: Int
        var goal: Int
        var due: Int
        var new: Int
    }

    func state(at date: Date, calendar: Calendar = .current) -> State {
        let later = daysSince(at: date, calendar: calendar)
        let due = dueNow + upcoming.count { $0 <= date }
        guard later > 0 else {
            return State(streak: streak, isDoneToday: isDoneToday, isAtRisk: streak > 0 && !isDoneToday, xp: xpToday, goal: goal, due: due, new: newLeft)
        }
        // Days gone by with no lesson, each taking a freeze while there is one.
        let missed = later - (isDoneToday ? 1 : 0)
        let kept = streak > 0 && missed <= freezes ? streak : 0
        return State(streak: kept, isDoneToday: false, isAtRisk: kept > 0, xp: 0, goal: goal, due: due, new: min(newPerDay, unseen))
    }

    /// Whole days from the snapshot's day to `date`'s.
    func daysSince(at date: Date, calendar: Calendar = .current) -> Int {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let made = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return 0 }
        return max(0, calendar.dateComponents([.day], from: made, to: calendar.startOfDay(for: date)).day ?? 0)
    }
}
