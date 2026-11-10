import Foundation

/// The settings, kept in UserDefaults: the keys and what they are before they are set.
enum Prefs {
    /// Experience points a day.
    static let goal = "xpGoal"
    /// New cards a day.
    static let newPerDay = "newPerDay"
    /// Say the answer aloud once it is shown.
    static let speak = "speakAnswers"
    static let sounds = "sounds"
    static let remind = "remind"
    /// When to remind, in minutes after midnight.
    static let remindAt = "remindAt"
    /// No listening until then: the learner said they cannot listen just now.
    static let quietUntil = "quietUntil"

    static var isQuiet: Bool {
        (UserDefaults.standard.object(forKey: quietUntil) as? Date).map { $0 > .now } ?? false
    }

    /// The goals to pick from, a lesson being about 100 XP.
    static let goals = [(100, "轻松"), (200, "正常"), (300, "认真"), (500, "拼命")]

    static func register() {
        let defaults = UserDefaults.standard
        // M1 counted lessons, three a day by default: about 100 XP each.
        if defaults.object(forKey: goal) == nil, let lessons = defaults.object(forKey: "dailyGoal") as? Int {
            defaults.set(min(500, max(100, lessons * 100)), forKey: goal)
        }
        defaults.register(defaults: [
            goal: 300,
            newPerDay: 10,
            speak: true,
            sounds: true,
            remind: true,
            remindAt: 20 * 60,
        ])
    }

    static var goalValue: Int { max(10, UserDefaults.standard.integer(forKey: goal)) }
    static var newPerDayValue: Int { UserDefaults.standard.integer(forKey: newPerDay) }
}
