import Foundation

/// The settings, kept in UserDefaults: the keys and what they are before they are set.
enum Prefs {
    /// Lessons a day.
    static let goal = "dailyGoal"
    /// New cards a day.
    static let newPerDay = "newPerDay"
    /// Say the answer aloud once it is shown.
    static let speak = "speakAnswers"
    static let remind = "remind"
    /// When to remind, in minutes after midnight.
    static let remindAt = "remindAt"

    static func register() {
        UserDefaults.standard.register(defaults: [
            goal: 3,
            newPerDay: 10,
            speak: true,
            remind: true,
            remindAt: 20 * 60,
        ])
    }

    static var goalValue: Int { max(1, UserDefaults.standard.integer(forKey: goal)) }
    static var newPerDayValue: Int { UserDefaults.standard.integer(forKey: newPerDay) }
}
