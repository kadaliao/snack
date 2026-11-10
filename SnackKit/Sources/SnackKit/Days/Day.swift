import Foundation

/// A day of the calendar, as it was where the learner was. A lesson is kept with
/// the day it was done on there, so flying across time zones does not move it.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone`, in the Gregorian calendar whatever
    /// calendar the phone shows.
    public init(_ date: Date, timeZone: TimeZone = .current) {
        let c = Self.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Reads "2026-11-10".
    public init?(_ text: String) {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The day `n` days later, or earlier for a negative `n`.
    public func adding(_ n: Int) -> Day {
        let utc = Self.gregorian(.gmt)
        let noon = utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        return Day(utc.date(byAdding: .day, value: n, to: noon) ?? noon, timeZone: .gmt)
    }

    /// When the day begins in `timeZone`.
    public func start(in timeZone: TimeZone = .current) -> Date {
        Self.gregorian(timeZone).date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// Sunday 1 to Saturday 7.
    public var weekday: Int {
        Self.gregorian(.gmt).component(.weekday, from: start(in: .gmt))
    }

    public static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }
}

/// Days in a row with at least one lesson, up to today, or up to yesterday while
/// today has none yet.
public struct Streak: Equatable, Sendable {
    public var count: Int
    public var isDoneToday: Bool
    public var longest: Int

    public init(days: Set<Day>, today: Day) {
        isDoneToday = days.contains(today)
        var day = isDoneToday ? today : today.adding(-1)
        var count = 0
        while days.contains(day) {
            count += 1
            day = day.adding(-1)
        }
        self.count = count

        var longest = 0
        var run = 0
        var previous: Day?
        for day in days.sorted() {
            run = previous.map { $0.adding(1) == day } == true ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        self.longest = longest
    }

    /// A streak that ends tonight unless a lesson is done today.
    public var isAtRisk: Bool { count > 0 && !isDoneToday }
}
