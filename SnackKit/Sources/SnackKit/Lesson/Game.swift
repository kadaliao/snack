import Foundation

/// The ways a card can be asked.
public enum Game: String, Codable, Sendable, CaseIterable {
    /// 选一选: four answers, one right.
    case choose
    /// 拼一拼: put the answer together from tiles, a few of them not in it.
    case build
    /// 默一默: type the answer.
    case type
    /// 翻一翻: think of it, turn the card over, and say how it went.
    case flip

    /// The best grade it can earn. A choice is right one time in four by chance,
    /// so it earns at most Hard.
    public var cap: Grade {
        switch self {
        case .choose: .hard
        case .build: .good
        case .type: .easy
        case .flip: .good
        }
    }

    /// How hard it is to get right; the hardest can earn Easy.
    public var level: Int {
        switch self {
        case .flip: 0
        case .choose: 1
        case .build: 2
        case .type: 3
        }
    }
}

/// One go at a question.
public struct Attempt: Sendable, Equatable {
    public var isCorrect: Bool
    /// Typed right but for a slip.
    public var hasTypo: Bool
    public var usedHint: Bool
    /// Asked for the answer instead.
    public var gaveUp: Bool
    public var seconds: Double
    /// For a flipped card: how the learner says it went.
    public var selfGrade: Grade?

    public init(isCorrect: Bool, hasTypo: Bool = false, usedHint: Bool = false, gaveUp: Bool = false, seconds: Double, selfGrade: Grade? = nil) {
        self.isCorrect = isCorrect
        self.hasTypo = hasTypo
        self.usedHint = usedHint
        self.gaveUp = gaveUp
        self.seconds = seconds
        self.selfGrade = selfGrade
    }

    /// A flipped card, graded by the learner: anything but Again is right.
    public static func flipped(_ grade: Grade, seconds: Double) -> Attempt {
        Attempt(isCorrect: grade != .again, seconds: seconds, selfGrade: grade)
    }

    public static func gaveUp(seconds: Double) -> Attempt {
        Attempt(isCorrect: false, gaveUp: true, seconds: seconds)
    }
}

/// From how a question went to the grade FSRS gets, so nobody grades by hand.
public enum Grading {
    /// Wrong, or the answer asked for: Again. Right, but with a hint or slowly: Hard.
    /// Right: Good; and right fast in the hardest game, with no slip: Easy. Never
    /// more than the game's cap.
    public static func grade(_ attempt: Attempt, for question: Question) -> Grade {
        let game = question.game
        if game == .flip { return min(attempt.selfGrade ?? .again, game.cap) }
        guard attempt.isCorrect, !attempt.gaveUp else { return .again }
        let slow = slowSeconds(question)
        let grade: Grade = if attempt.usedHint || attempt.seconds > slow {
            .hard
        } else if game.level == 3 && !attempt.hasTypo && attempt.seconds < slow / 2 {
            .easy
        } else {
            .good
        }
        return min(grade, game.cap)
    }

    /// Longer than this to get it right counts as a struggle. It grows with the
    /// answer: reading a long one, putting it together, typing it, all take longer.
    public static func slowSeconds(_ question: Question) -> Double {
        let letters = Double(question.card.back.count)
        return switch question.game {
        case .choose: 8 + 0.1 * letters
        case .build: 6 + 2.5 * Double(question.answerTiles)
        case .type: 8 + 0.8 * letters
        case .flip: .infinity
        }
    }
}
