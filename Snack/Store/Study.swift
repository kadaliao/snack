import Foundation
import Observation
import SnackKit
import SwiftData

/// One review, as kept. Every field has a default and nothing is unique, so the
/// log can sync through CloudKit later without two devices fighting over a row.
@Model
final class ReviewRecord {
    var id: UUID = UUID()
    var deck: String = ""
    var card: String = ""
    var grade: Int = 3
    var at: Date = Date.distantPast
    var game: String?
    var seconds: Double = 0
    var source: String = Review.Source.lesson.rawValue

    init(_ review: Review) {
        id = review.id
        deck = review.card.deck
        card = review.card.card
        grade = review.grade.rawValue
        at = review.at
        game = review.game?.rawValue
        seconds = review.seconds
        source = review.source.rawValue
    }

    var review: Review? {
        guard let grade = Grade(rawValue: grade) else { return nil }
        return Review(
            id: id, card: CardKey(deck: deck, card: card), grade: grade, at: at,
            game: game.flatMap(Game.init(rawValue:)), seconds: seconds,
            source: Review.Source(rawValue: source) ?? .lesson
        )
    }
}

/// A lesson finished, with the day it was finished on where the learner was.
@Model
final class LessonRecord {
    var id: UUID = UUID()
    var finishedAt: Date = Date.distantPast
    var day: String = ""
    var questions: Int = 0
    var correct: Int = 0
    var seconds: Double = 0
    var deck: String?

    init(finishedAt: Date, day: Day, questions: Int, correct: Int, seconds: Double, deck: String?) {
        self.finishedAt = finishedAt
        self.day = day.description
        self.questions = questions
        self.correct = correct
        self.seconds = seconds
        self.deck = deck
    }
}

/// The learner's progress: the review log and the lessons, kept on the phone, and
/// what follows from them (each card's memory, the streak, the day's lessons).
@MainActor
@Observable
final class Study {
    let scheduler = Scheduler()
    private(set) var progress = Progress()
    private(set) var lessonsByDay: [Day: Int] = [:]
    /// Why progress cannot be kept, if it cannot.
    private(set) var problem: String?

    @ObservationIgnored private var container: ModelContainer?

    init(inMemory: Bool = false) {
        do {
            // No CloudKit yet: one device, and the log alone, until M3.
            let config = ModelConfiguration("Progress", isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            container = try ModelContainer(for: ReviewRecord.self, LessonRecord.self, configurations: config)
        } catch {
            problem = "复习记录存不下来：\(error.localizedDescription)"
        }
        load()
    }

    private var context: ModelContext? { container?.mainContext }

    private func load() {
        guard let context else { return }
        do {
            let reviews = try context.fetch(FetchDescriptor<ReviewRecord>()).compactMap(\.review)
            progress = Progress(reviews, scheduler: scheduler)
            let lessons = try context.fetch(FetchDescriptor<LessonRecord>())
            lessonsByDay = Dictionary(grouping: lessons.compactMap { Day($0.day) }, by: { $0 }).mapValues(\.count)
        } catch {
            problem = "读不出复习记录：\(error.localizedDescription)"
        }
    }

    func record(_ review: Review) {
        progress.apply(review, scheduler)
        context?.insert(ReviewRecord(review))
        save()
    }

    /// Fix cards whose mistake a producer saw made again: each counts as forgotten.
    func recordRepeated(_ keys: [CardKey], at now: Date = .now) {
        for key in keys {
            record(Review(card: key, grade: .again, at: now, source: .repeated))
        }
    }

    func finishLesson(_ run: LessonRun, started: Date, deck: String?, at now: Date = .now) {
        let day = Day(now)
        context?.insert(LessonRecord(
            finishedAt: now, day: day, questions: run.graded.count, correct: run.correct,
            seconds: now.timeIntervalSince(started), deck: deck
        ))
        save()
        lessonsByDay[day, default: 0] += 1
    }

    private func save() {
        do {
            try context?.save()
        } catch {
            problem = "复习记录没存上：\(error.localizedDescription)"
        }
    }

    // MARK: - What follows

    func streak(at now: Date = .now) -> Streak {
        Streak(days: Set(lessonsByDay.keys), today: Day(now))
    }

    func lessons(on day: Day) -> Int {
        lessonsByDay[day] ?? 0
    }

    /// New cards today still allowed.
    func newLeft(at now: Date = .now, perDay: Int = Prefs.newPerDayValue) -> Int {
        max(0, perDay - progress.introducedCount(on: Day(now)))
    }

    func mastery(_ key: CardKey) -> Mastery {
        Mastery(progress.memories[key])
    }

    /// A lesson of `entries` now; `extraNew` new cards on top of the day's allowance.
    func plan(_ entries: [Entry], extraNew: Int = 0, at now: Date = .now) -> [Question] {
        var rng = SplitMix64()
        let questions = Planner().plan(
            entries, progress: progress, scheduler: scheduler, now: now,
            newLeft: newLeft(at: now) + extraNew, using: &rng
        )
        #if DEBUG
        // `-SnackGames build,type,flip,choose`: the games in turn, for the UI test.
        let games = (UserDefaults.standard.string(forKey: "SnackGames") ?? "").split(separator: ",").compactMap { Game(rawValue: String($0)) }
        if !games.isEmpty {
            let byDeck = Dictionary(grouping: entries, by: \.key.deck)
            return questions.enumerated().map { i, q in
                Questions.make(q.entry, memory: progress.memories[q.key], siblings: byDeck[q.key.deck] ?? [], using: &rng, game: games[i % games.count])
            }
        }
        #endif
        return questions
    }

    /// Puts the reminders of the coming days in line with how today stands.
    func syncReminders(at now: Date = .now) async {
        let today = Day(now)
        await Reminders.reschedule(streak: streak(at: now), lessonsToday: lessons(on: today), goal: Prefs.goalValue, now: now)
    }
}
