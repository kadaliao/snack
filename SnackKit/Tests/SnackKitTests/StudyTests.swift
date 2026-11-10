import Foundation
import Testing

@testable import SnackKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let key = CardKey(deck: "d", card: "a")
private let scheduler = Scheduler()

@Test func aNewCardLearnsInMinutesThenGoesToDays() {
    let again = scheduler.review(nil, .again, at: t0)
    #expect(again.phase == .learning)
    #expect(again.due == t0.addingTimeInterval(60))

    let good = scheduler.review(nil, .good, at: t0)
    #expect(good.phase == .learning)
    #expect(good.due == t0.addingTimeInterval(600))

    // Good again after its ten minutes: it graduates to days.
    let graduated = scheduler.review(good, .good, at: good.due)
    #expect(graduated.phase == .review)
    #expect(graduated.due.timeIntervalSince(good.due) >= 86_400)

    // Hard keeps it at the step it is on.
    let hard = scheduler.review(nil, .hard, at: t0)
    #expect(hard.phase == .learning)
    #expect(hard.step == 0)

    let easy = scheduler.review(nil, .easy, at: t0)
    #expect(easy.phase == .review)
    #expect(easy.stability > graduated.stability)
}

@Test func forgettingAReviewCardRelearnsIt() {
    var m = scheduler.review(nil, .easy, at: t0)
    m = scheduler.review(m, .again, at: m.due)
    #expect(m.phase == .relearning)
    #expect(m.lapses == 1)
    #expect(scheduler.retrievability(m, at: m.lastReview) > 0.99)
}

@Test func progressIsTheReviewsPlayedBackInOrder() {
    let reviews = [
        Review(card: key, grade: .good, at: t0),
        Review(card: key, grade: .good, at: t0.addingTimeInterval(700)),
        Review(card: key, grade: .again, at: t0.addingTimeInterval(5 * 86_400)),
    ]
    var step = Progress()
    for r in reviews { step.apply(r, scheduler) }
    #expect(Progress(reviews.reversed(), scheduler: scheduler) == step)

    var direct = scheduler.review(nil, .good, at: reviews[0].at)
    direct = scheduler.review(direct, .good, at: reviews[1].at)
    direct = scheduler.review(direct, .again, at: reviews[2].at)
    #expect(step.memories[key] == direct)
}

@Test func onlyLessonsIntroduceCards() {
    let other = CardKey(deck: "d", card: "b")
    let p = Progress([
        Review(card: key, grade: .again, at: t0, source: .repeated),
        Review(card: other, grade: .good, at: t0),
    ], scheduler: scheduler)
    #expect(p.memories.count == 2)
    #expect(p.introduced.keys.sorted { $0.card < $1.card } == [other])
    #expect(p.introducedCount(on: Day(t0, timeZone: .gmt), timeZone: .gmt) == 1)
    #expect(p.introducedCount(on: Day(t0, timeZone: .gmt).adding(1), timeZone: .gmt) == 0)
}

@Test func masteryGoesByHowLongACardHolds() {
    #expect(Mastery(nil) == .new)
    let learning = scheduler.review(nil, .good, at: t0)
    #expect(Mastery(learning) == .learning)
    var m = learning
    m.phase = .review
    for (s, level) in [(0.5, Mastery.learning), (3, .young), (10, .familiar), (40, .strong), (120, .mastered)] {
        m.stability = s
        #expect(Mastery(m) == level)
    }
}

// MARK: - Days

@Test func daysReadWriteAndCount() {
    let d = Day("2026-12-31")
    #expect(d == Day(year: 2026, month: 12, day: 31))
    #expect(d?.description == "2026-12-31")
    #expect(d?.adding(1) == Day(year: 2027, month: 1, day: 1))
    #expect(Day(year: 2028, month: 3, day: 1).adding(-1) == Day(year: 2028, month: 2, day: 29))
    #expect(Day("2026-13-01") == nil)
    #expect(Day("yesterday") == nil)
    #expect(Day(year: 2026, month: 11, day: 10).weekday == 3)  // a Tuesday
}

@Test func aMomentIsADayWhereTheLearnerIs() {
    // 2026-11-10 23:30 in Shanghai is still the morning of the 10th in New York.
    let late = Date(timeIntervalSince1970: 1_794_324_600)  // 2026-11-10T15:30:00Z
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let newYork = TimeZone(identifier: "America/New_York")!
    #expect(Day(late, timeZone: shanghai) == Day(year: 2026, month: 11, day: 10))
    #expect(Day(late.addingTimeInterval(3600), timeZone: shanghai) == Day(year: 2026, month: 11, day: 11))
    #expect(Day(late.addingTimeInterval(3600), timeZone: newYork) == Day(year: 2026, month: 11, day: 10))
    #expect(Day(year: 2026, month: 11, day: 10).start(in: shanghai) == Date(timeIntervalSince1970: 1_794_240_000))
}

@Test func aStreakCountsDaysInARow() {
    let today = Day(year: 2026, month: 11, day: 10)
    let days = Set([-1, -2, -3, -6, -7].map { today.adding($0) })

    let waiting = Streak(days: days, today: today)
    #expect(waiting.count == 3)
    #expect(!waiting.isDoneToday)
    #expect(waiting.isAtRisk)
    #expect(waiting.longest == 3)

    let done = Streak(days: days.union([today]), today: today)
    #expect(done.count == 4)
    #expect(done.isDoneToday)
    #expect(!done.isAtRisk)

    // A day missed: it starts over.
    let broken = Streak(days: days, today: today.adding(1))
    #expect(broken.count == 0)
    #expect(!broken.isAtRisk)
    #expect(Streak(days: [], today: today) == Streak(days: [], today: today.adding(9)))
}

@Test func aLessonKeepsTheDayItWasDoneOnAcrossTimeZones() {
    // Lessons on the 9th and the 10th in Shanghai, the second at 23:30 there.
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let newYork = TimeZone(identifier: "America/New_York")!
    let second = Date(timeIntervalSince1970: 1_794_324_600)
    let kept: Set<Day> = [Day(second.addingTimeInterval(-86_400), timeZone: shanghai), Day(second, timeZone: shanghai)]
    // Landing in New York on what is there still the 10th: the streak holds and today is done.
    let today = Day(second.addingTimeInterval(12 * 3600), timeZone: newYork)
    #expect(today == Day(year: 2026, month: 11, day: 10))
    let streak = Streak(days: kept, today: today)
    #expect(streak.count == 2)
    #expect(streak.isDoneToday)
}
