import FSRS
import Foundation

/// How well a card is held, as FSRS-6 sees it after the card's reviews. A card
/// never reviewed has none.
public struct Memory: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable {
        /// Met lately: back within minutes until it sticks.
        case learning
        /// Spaced out over days.
        case review
        /// Forgotten after it had stuck: back within minutes again.
        case relearning
    }

    public var phase: Phase
    public var due: Date
    /// About how many days until it is as likely forgotten as the retention aimed for allows.
    public var stability: Double
    public var difficulty: Double
    public var step: Int
    public var reps: Int
    public var lapses: Int
    public var lastReview: Date
    public var scheduledDays: Double

    public init(
        phase: Phase, due: Date, stability: Double, difficulty: Double, step: Int = 0,
        reps: Int, lapses: Int, lastReview: Date, scheduledDays: Double = 0
    ) {
        self.phase = phase
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.step = step
        self.reps = reps
        self.lapses = lapses
        self.lastReview = lastReview
        self.scheduledDays = scheduledDays
    }
}

/// How a review went, as FSRS takes it.
public enum Grade: Int, Codable, Sendable, CaseIterable, Comparable {
    case again = 1, hard, good, easy

    public static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }
}

/// FSRS-6 with its default weights, learning steps of 1 and 10 minutes, and 90% of
/// cards meant to be remembered when they come due.
public struct Scheduler: Sendable {
    private let fsrs: FSRS

    public init(retention: Double = 0.9) {
        fsrs = FSRS(parameters: FSRSParameters(
            requestRetention: retention,
            w: FSRSDefaults.defaultWv6,
            enableFuzz: false,
            enableShortTerm: true
        ))
    }

    /// The memory after a review graded `grade` at `time`; `memory` nil for a card
    /// met for the first time.
    public func review(_ memory: Memory?, _ grade: Grade, at time: Date) -> Memory {
        let card = memory.map(Self.card) ?? Card(due: time)
        let rating = Rating(rawValue: grade.rawValue) ?? .good
        guard let next = try? fsrs.next(card: card, now: time, grade: rating) else {
            // Only a manual rating or broken steps throw; neither happens here.
            return memory ?? Memory(phase: .learning, due: time, stability: 0, difficulty: 0, reps: 1, lapses: 0, lastReview: time)
        }
        return Self.memory(next.card, reviewed: time)
    }

    /// How likely the card is still remembered at `time`, 0 to 1.
    public func retrievability(_ memory: Memory, at time: Date) -> Double {
        fsrs.getRetrievability(card: Self.card(memory), now: time).number
    }

    private static func card(_ m: Memory) -> Card {
        let state: CardState = switch m.phase {
        case .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
        return Card(
            due: m.due, stability: m.stability, difficulty: m.difficulty, scheduledDays: m.scheduledDays,
            learningSteps: m.step, reps: m.reps, lapses: m.lapses, state: state, lastReview: m.lastReview
        )
    }

    private static func memory(_ c: Card, reviewed time: Date) -> Memory {
        let phase: Memory.Phase = switch c.state {
        case .new, .learning: .learning
        case .review: .review
        case .relearning: .relearning
        }
        return Memory(
            phase: phase, due: c.due, stability: c.stability, difficulty: c.difficulty, step: c.learningSteps,
            reps: c.reps, lapses: c.lapses, lastReview: c.lastReview ?? time, scheduledDays: c.scheduledDays
        )
    }
}
