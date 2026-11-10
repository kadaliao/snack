import Foundation

/// The ways a card can be asked, from easiest to hardest.
public enum Game: String, Codable, Sendable, CaseIterable {
    /// 选一选: four answers, one right.
    case choose
    /// 配一配: five fronts and five backs, paired up. Several cards at once.
    case match
    /// 拼一拼: put the answer together from tiles, a few of them not in it.
    case build
    /// 听一听: hear the answer said, and put it together from tiles, or pick
    /// what it means when it is too short to put together.
    case listen
    /// 填一填: the example sentence with the answer taken out; type it in.
    case cloze
    /// 默一默: type the answer.
    case type
    /// 改一改: what the learner wrote, to edit into the better way to say it.
    case fix
    /// 翻一翻: think of it, turn the card over, and say how it went.
    case flip

    /// The best grade it can earn. A choice is right one time in four by chance,
    /// so it earns at most Hard; so does pairing, where the last pair is given.
    public var cap: Grade {
        switch self {
        case .choose, .match: .hard
        case .build, .listen, .cloze, .fix, .flip: .good
        case .type: .easy
        }
    }

    /// How hard it is to get right.
    public var level: Int {
        switch self {
        case .flip: 0
        case .choose, .match: 1
        case .build, .listen, .cloze: 2
        case .type, .fix: 3
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
    /// For pairing: the cards whose front was put with a wrong back.
    public var missed: Set<CardKey>

    public init(
        isCorrect: Bool, hasTypo: Bool = false, usedHint: Bool = false, gaveUp: Bool = false,
        seconds: Double, selfGrade: Grade? = nil, missed: Set<CardKey> = []
    ) {
        self.isCorrect = isCorrect
        self.hasTypo = hasTypo
        self.usedHint = usedHint
        self.gaveUp = gaveUp
        self.seconds = seconds
        self.selfGrade = selfGrade
        self.missed = missed
    }

    /// A flipped card, graded by the learner: anything but Again is right.
    public static func flipped(_ grade: Grade, seconds: Double) -> Attempt {
        Attempt(isCorrect: grade != .again, seconds: seconds, selfGrade: grade)
    }

    public static func gaveUp(seconds: Double) -> Attempt {
        Attempt(isCorrect: false, gaveUp: true, seconds: seconds)
    }

    /// All pairs made, with these cards' fronts put wrong at some point.
    public static func matched(missing: Set<CardKey>, seconds: Double) -> Attempt {
        Attempt(isCorrect: missing.isEmpty, seconds: seconds, missed: missing)
    }
}

/// From how a question went to the grade FSRS gets, so nobody grades by hand.
public enum Grading {
    /// Wrong, or the answer asked for: Again. Right, but with a hint or slowly: Hard.
    /// Right: Good; and right fast when typing it out, with no slip: Easy. Never
    /// more than the question's cap.
    public static func grade(_ attempt: Attempt, for question: Question) -> Grade {
        let cap = question.cap
        if question.game == .flip { return min(attempt.selfGrade ?? .again, cap) }
        guard attempt.isCorrect, !attempt.gaveUp else { return .again }
        let slow = slowSeconds(question)
        let grade: Grade = if attempt.usedHint || attempt.seconds > slow {
            .hard
        } else if question.game == .type && !attempt.hasTypo && attempt.seconds < slow / 2 {
            .easy
        } else {
            .good
        }
        return min(grade, cap)
    }

    /// A card of a pairing: right if its front was never put wrong.
    public static func grade(paired key: CardKey, in attempt: Attempt) -> Grade {
        attempt.missed.contains(key) ? .again : Game.match.cap
    }

    /// Longer than this to get it right counts as a struggle. It grows with the
    /// answer: reading a long one, putting it together, typing it, all take longer.
    public static func slowSeconds(_ question: Question) -> Double {
        let letters = Double(question.card.back.count)
        return switch question.game {
        case .choose: 8 + 0.1 * letters
        case .build: 6 + 2.5 * Double(question.answerTiles)
        case .listen: question.tiles.isEmpty ? 10 : 8 + 2.5 * Double(question.answerTiles)
        case .type, .cloze: 8 + 0.8 * letters
        case .fix: 10 + 0.6 * letters
        case .match, .flip: .infinity
        }
    }
}

/// Experience points: what a lesson earns, to aim a day's goal at.
public enum Score {
    /// A first answer right.
    public static let answer = 10
    /// A card of a pairing put right first time.
    public static let pair = 5
    /// Right the second time, at the end of the lesson.
    public static let practice = 5
    /// Right answers in a row from which each earns a bonus, and the bonus.
    public static let comboFrom = 5
    public static let comboBonus = 5
    /// A lesson finished, and one finished without a wrong first answer.
    public static let finished = 10
    public static let perfect = 20
}
