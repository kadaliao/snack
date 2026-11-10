import Foundation
import SnackKit
import WidgetKit

/// Keeps the widget's snapshot in step with the app.
@MainActor
enum WidgetBridge {
    static func update(library: Library, study: Study, now: Date = .now) {
        let entries = library.entries()
        let today = Day(now)
        let streak = study.streak(at: now)
        let planner = Planner()
        let outlook = planner.outlook(entries, progress: study.progress, now: now, newLeft: study.newLeft(at: now))
        // When each card not yet due starts to count as due: a card in learning a
        // little before its time, a card in review on its day.
        let horizon = now.addingTimeInterval(2 * 86_400)
        let end = today.adding(1).start()
        var upcoming: [Date] = []
        for e in entries {
            guard let m = study.progress.memories[e.key] else { continue }
            let counted = m.phase == .review ? Day(m.due).start() : m.due.addingTimeInterval(-planner.learnAhead)
            if !planner.isDue(m, now: now, endOfDay: end), counted > now, counted < horizon {
                upcoming.append(counted)
            }
        }
        let snapshot = WidgetSnapshot(
            day: today.description, streak: streak.count, isDoneToday: streak.isDoneToday, freezes: streak.freezes,
            xpToday: study.xp(on: today), goal: Prefs.goalValue, dueNow: outlook.due,
            upcoming: Array(upcoming.sorted().prefix(300)), newLeft: outlook.new, newPerDay: Prefs.newPerDayValue,
            unseen: outlook.unseen, updatedAt: now
        )
        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
