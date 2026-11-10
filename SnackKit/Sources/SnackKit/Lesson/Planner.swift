import Foundation

/// Choosing the cards of a lesson: those due first, the most likely forgotten
/// first, with a few new ones mixed in while the day's new cards last.
public struct Planner: Sendable {
    /// Questions in a lesson, before any asked again.
    public var size: Int
    /// A card in learning due within this long counts as due, so a lesson soon
    /// after another still has them.
    public var learnAhead: TimeInterval
    /// Fewer due and new cards than this and the lesson takes cards not yet due,
    /// the most likely forgotten first.
    public var least: Int
    /// New cards saved room for in a lesson even when there is more than enough due.
    public var newReserved: Int

    public init(size: Int = 10, learnAhead: TimeInterval = 20 * 60, least: Int = 5, newReserved: Int = 2) {
        self.size = size
        self.learnAhead = learnAhead
        self.least = least
        self.newReserved = newReserved
    }

    /// What a lesson started now would find.
    public struct Outlook: Equatable, Sendable {
        /// Cards due.
        public var due: Int
        /// New cards it may bring: the day's allowance left, or fewer if fewer are unseen.
        public var new: Int
        /// Cards never studied.
        public var unseen: Int
        /// Cards studied at least once.
        public var studied: Int
    }

    public func outlook(_ entries: [Entry], progress: Progress, now: Date, timeZone: TimeZone = .current, newLeft: Int) -> Outlook {
        let end = Day(now, timeZone: timeZone).adding(1).start(in: timeZone)
        var due = 0, unseen = 0
        for e in entries {
            if let m = progress.memories[e.key] {
                if isDue(m, now: now, endOfDay: end) { due += 1 }
            } else {
                unseen += 1
            }
        }
        return Outlook(due: due, new: min(max(newLeft, 0), unseen), unseen: unseen, studied: entries.count - unseen)
    }

    /// A card in learning is due at its time (or a little before); a card in
    /// review on its day.
    public func isDue(_ m: Memory, now: Date, endOfDay: Date) -> Bool {
        m.phase == .review ? m.due < endOfDay : m.due <= now.addingTimeInterval(learnAhead)
    }

    /// The questions of a lesson, shuffled; none when there is nothing to study
    /// and no new card left for today.
    public func plan<R: RandomNumberGenerator>(
        _ entries: [Entry], progress: Progress, scheduler: Scheduler, now: Date, timeZone: TimeZone = .current,
        newLeft: Int, using rng: inout R
    ) -> [Question] {
        let end = Day(now, timeZone: timeZone).adding(1).start(in: timeZone)
        var due: [(entry: Entry, memory: Memory, r: Double)] = []
        var ahead: [(entry: Entry, memory: Memory, r: Double)] = []
        var fresh: [Entry] = []
        for e in entries {
            guard let m = progress.memories[e.key] else {
                fresh.append(e)
                continue
            }
            let item = (e, m, scheduler.retrievability(m, at: now))
            if isDue(m, now: now, endOfDay: end) { due.append(item) } else { ahead.append(item) }
        }
        // Learning cards first, by when they were due; then the rest, the least
        // likely still remembered first.
        due.sort { a, b in
            let la = a.memory.phase != .review, lb = b.memory.phase != .review
            if la != lb { return la }
            return la ? a.memory.due < b.memory.due : a.r < b.r
        }
        ahead.sort { $0.r < $1.r }

        let newCap = min(max(newLeft, 0), fresh.count)
        let takeDue = min(due.count, size - min(newCap, newReserved))
        let takeNew = min(newCap, size - takeDue)
        var picked: [(Entry, Memory?)] = due.prefix(takeDue).map { ($0.entry, $0.memory) }
        picked += fresh.prefix(takeNew).map { ($0, nil) }
        if picked.count < least {
            picked += ahead.prefix(size - picked.count).map { ($0.entry, $0.memory) }
        }
        picked.shuffle(using: &rng)

        let byDeck = Dictionary(grouping: entries, by: \.key.deck)
        return picked.map { entry, memory in
            Questions.make(entry, memory: memory, siblings: byDeck[entry.key.deck] ?? [], using: &rng)
        }
    }
}

/// A lesson under way: its questions in order, each answer, and the wrong ones
/// asked once more at the end.
///
/// Only a question's first time counts for FSRS: a card asked again after a wrong
/// answer is practice, so its grade is nil.
public struct LessonRun: Sendable {
    public struct Result: Sendable, Equatable {
        public var question: Question
        public var attempt: Attempt
        /// The grade for FSRS; nil for practice.
        public var grade: Grade?
        public var isCorrect: Bool
    }

    public private(set) var questions: [Question]
    public private(set) var index = 0
    public private(set) var results: [Result] = []
    /// Right answers in a row, and the most in a row so far.
    public private(set) var combo = 0
    public private(set) var bestCombo = 0
    private var rng: SplitMix64

    public init(_ questions: [Question], seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.questions = questions
        rng = SplitMix64(seed: seed)
    }

    public var current: Question? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    /// The current question has its answer and waits for `advance()`.
    public var isAnswered: Bool { results.count > index }
    public var isFinished: Bool { index >= questions.count }

    /// How far along, 0 to 1: answers given over questions there are, the ones
    /// asked again included.
    public var progress: Double {
        questions.isEmpty ? 1 : Double(results.count) / Double(questions.count)
    }

    /// Takes the answer to the current question. A wrong first answer brings the
    /// card back at the end.
    @discardableResult
    public mutating func answer(_ attempt: Attempt) -> Result? {
        guard let q = current, !isAnswered else { return nil }
        let isCorrect = attempt.isCorrect && !attempt.gaveUp
        let grade = q.isRetry ? nil : Grading.grade(attempt, for: q)
        combo = isCorrect ? combo + 1 : 0
        bestCombo = max(bestCombo, combo)
        if !isCorrect && !q.isRetry { questions.append(q.retry(using: &rng)) }
        let result = Result(question: q, attempt: attempt, grade: grade, isCorrect: isCorrect)
        results.append(result)
        return result
    }

    public mutating func advance() {
        guard isAnswered else { return }
        index += 1
    }

    /// The first answers, the ones that count.
    public var graded: [Result] { results.filter { $0.grade != nil } }

    public var correct: Int { graded.count { $0.isCorrect } }

    public var accuracy: Double {
        graded.isEmpty ? 0 : Double(correct) / Double(graded.count)
    }
}
