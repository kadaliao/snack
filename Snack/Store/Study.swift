import CloudKit
import CoreData
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
    /// Experience points; 0 in lessons from before they were counted.
    var xp: Int = 0

    init(finishedAt: Date, day: Day, questions: Int, correct: Int, seconds: Double, deck: String?, xp: Int) {
        self.finishedAt = finishedAt
        self.day = day.description
        self.questions = questions
        self.correct = correct
        self.seconds = seconds
        self.deck = deck
        self.xp = xp
    }

    /// What it earned, or for a lesson from before points, what it would have.
    var points: Int {
        xp > 0 ? xp : correct * Score.answer + Score.finished
    }
}

/// The learner's progress: the review log and the lessons, kept on the device and
/// synced through the learner's private CloudKit database, and what follows from
/// them (each card's memory, the streak, the day's XP). Reviews from another
/// device come in any order; the log is played back again, in order, each time.
@MainActor
@Observable
final class Study {
    let scheduler = Scheduler()
    private(set) var progress = Progress()
    private(set) var lessonsByDay: [Day: Int] = [:]
    private(set) var xpByDay: [Day: Int] = [:]
    /// Why progress cannot be kept, if it cannot.
    private(set) var problem: String?
    /// How syncing went last.
    private(set) var sync: Sync = .waiting

    enum Sync: Equatable {
        case waiting
        case off
        case done(Date)
        case failed(String)
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var reloading: Task<Void, Never>?

    init(inMemory: Bool = false) {
        #if DEBUG
        // `-SnackInitCloudKitSchema YES`: puts the record types in CloudKit's
        // development environment, to deploy to production from the console.
        if UserDefaults.standard.bool(forKey: "SnackInitCloudKitSchema") { Self.initializeCloudKitSchema() }
        #endif
        do {
            let config = ModelConfiguration(
                "Progress", isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: inMemory ? .none : .private(Inbox.containerID)
            )
            container = try ModelContainer(for: ReviewRecord.self, LessonRecord.self, configurations: config)
        } catch {
            problem = "复习记录存不下来：\(error.localizedDescription)"
        }
        if inMemory { sync = .off }
        load()
        watchSync()
    }

    private var context: ModelContext? { container?.mainContext }

    #if DEBUG
    /// Core Data's way, on a store of its own in Caches: SwiftData has none.
    private static func initializeCloudKitSchema() {
        let url = URL.cachesDirectory.appending(path: "schema-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Inbox.containerID)
        description.shouldAddStoreAsynchronously = false
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [ReviewRecord.self, LessonRecord.self]) else {
            print("CloudKit schema: no model")
            return
        }
        let container = NSPersistentCloudKitContainer(name: "Schema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure {
            print("CloudKit schema: store failed: \(failure)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            print("CloudKit schema: initialized")
        } catch {
            print("CloudKit schema: failed: \(error)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: url)
    }
    #endif

    private func load() {
        guard let context else { return }
        lessonsByDay = [:]
        xpByDay = [:]
        do {
            let reviews = try context.fetch(FetchDescriptor<ReviewRecord>()).compactMap(\.review)
            progress = Progress(reviews, scheduler: scheduler)
            for lesson in try context.fetch(FetchDescriptor<LessonRecord>()) {
                guard let day = Day(lesson.day) else { continue }
                lessonsByDay[day, default: 0] += 1
                xpByDay[day, default: 0] += lesson.points
            }
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
            seconds: now.timeIntervalSince(started), deck: deck, xp: run.xp
        ))
        save()
        lessonsByDay[day, default: 0] += 1
        xpByDay[day, default: 0] += run.xp
    }

    /// Reviews and lessons from other devices come in through CloudKit: play the
    /// log back again once they stop coming for a moment. And keep how syncing went.
    private func watchSync() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadSoon() }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let end = event.endDate
            else { return }
            let failure = event.error.map { error in
                (error as? CKError)?.code == .notAuthenticated ? "没有登录 iCloud" : (error as NSError).localizedDescription
            }
            MainActor.assumeIsolated {
                guard let self else { return }
                if let failure { self.sync = .failed(failure) } else if event.succeeded { self.sync = .done(end) }
            }
        })
    }

    private func reloadSoon() {
        reloading?.cancel()
        reloading = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            load()
        }
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
        Streak(lessons: lessonsByDay, today: Day(now))
    }

    func lessons(on day: Day) -> Int {
        lessonsByDay[day] ?? 0
    }

    func xp(on day: Day) -> Int {
        xpByDay[day] ?? 0
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
        // `-SnackGames match,listen,…`: for the UI test, a pairing if the list has
        // one, and the other questions in the other games in turn.
        let games = (UserDefaults.standard.string(forKey: "SnackGames") ?? "").split(separator: ",").compactMap { Game(rawValue: String($0)) }
        if !games.isEmpty {
            let byDeck = Dictionary(grouping: entries, by: \.key.deck)
            var made = questions.filter { $0.game != .match }
            if games.contains(.match) {
                if let pairing = questions.first(where: { $0.game == .match }) {
                    made.insert(pairing, at: 0)
                } else if let i = made.firstIndex(where: { Questions.isMatchable($0.entry) }) {
                    let q = made.remove(at: i)
                    made.insert(Questions.make(q.entry, memory: progress.memories[q.key], siblings: byDeck[q.key.deck] ?? [], using: &rng, game: .match), at: 0)
                }
            }
            let rest = games.filter { $0 != .match }
            return made.enumerated().map { i, q in
                q.game == .match || rest.isEmpty ? q
                    : Questions.make(q.entry, memory: progress.memories[q.key], siblings: byDeck[q.key.deck] ?? [], using: &rng, game: rest[(i - (games.contains(.match) ? 1 : 0) + rest.count) % rest.count])
            }
        }
        #endif
        return questions
    }

    /// Puts the reminders of the coming days in line with how today stands.
    func syncReminders(at now: Date = .now) async {
        await Reminders.reschedule(streak: streak(at: now), xpToday: xp(on: Day(now)), goal: Prefs.goalValue, now: now)
    }
}
