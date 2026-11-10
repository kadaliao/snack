import Foundation

/// One review of one card: the only thing the app keeps of its own. Everything
/// else about progress (each card's memory, what is due, how many new cards
/// today) is worked out again from these, in order.
public struct Review: Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// Answered in a lesson.
        case lesson
        /// A producer saw the learner make a fix card's mistake again.
        case repeated
    }

    public var id: UUID
    public var card: CardKey
    public var grade: Grade
    public var at: Date
    public var game: Game?
    public var seconds: Double
    public var source: Source

    public init(id: UUID = UUID(), card: CardKey, grade: Grade, at: Date, game: Game? = nil, seconds: Double = 0, source: Source = .lesson) {
        self.id = id
        self.card = card
        self.grade = grade
        self.at = at
        self.game = game
        self.seconds = seconds
        self.source = source
    }
}

/// Every card's memory, from the reviews played back in order.
public struct Progress: Sendable, Equatable {
    public private(set) var memories: [CardKey: Memory] = [:]
    /// When each card was first met in a lesson: the new cards of a day are counted by it.
    public private(set) var introduced: [CardKey: Date] = [:]

    public init() {}

    /// Plays the reviews back, the earliest first, whatever order they come in.
    public init(_ reviews: [Review], scheduler: Scheduler) {
        let ordered = reviews.sorted { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) }
        for review in ordered { apply(review, scheduler) }
    }

    /// Adds a review later than all before it.
    public mutating func apply(_ review: Review, _ scheduler: Scheduler) {
        memories[review.card] = scheduler.review(memories[review.card], review.grade, at: review.at)
        if review.source == .lesson, introduced[review.card] == nil {
            introduced[review.card] = review.at
        }
    }

    /// How many cards were met for the first time on `day`.
    public func introducedCount(on day: Day, timeZone: TimeZone = .current) -> Int {
        introduced.values.count { Day($0, timeZone: timeZone) == day }
    }
}

/// How well a card is known, in steps a person can see: by how long it holds.
public enum Mastery: Int, Sendable, Comparable, CaseIterable {
    case new, learning, young, familiar, strong, mastered

    public init(_ memory: Memory?) {
        guard let m = memory else { self = .new; return }
        if m.phase != .review || m.stability < 1 { self = .learning; return }
        switch m.stability {
        case ..<7: self = .young
        case ..<21: self = .familiar
        case ..<90: self = .strong
        default: self = .mastered
        }
    }

    public static func < (a: Mastery, b: Mastery) -> Bool { a.rawValue < b.rawValue }
}
