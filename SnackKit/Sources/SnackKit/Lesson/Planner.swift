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
    /// Cards in a pairing, made of new and learning cards when a lesson has this
    /// many short ones of a deck; 0 for none.
    public var pairing: Int

    public init(size: Int = 10, learnAhead: TimeInterval = 20 * 60, least: Int = 5, newReserved: Int = 2, pairing: Int = 5) {
        self.size = size
        self.learnAhead = learnAhead
        self.least = least
        self.newReserved = newReserved
        self.pairing = pairing
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
        var picked: [(entry: Entry, memory: Memory?)] = due.prefix(takeDue).map { ($0.entry, $0.memory) }
        picked += fresh.prefix(takeNew).map { ($0, nil) }
        // What comes next, should a pairing free room.
        var spare: [(entry: Entry, memory: Memory?)] = due.dropFirst(takeDue).map { ($0.entry, $0.memory) }
        spare += fresh.dropFirst(takeNew).prefix(newCap - takeNew).map { ($0, nil) }
        if picked.count < least {
            let more = ahead.prefix(size - picked.count)
            picked += more.map { ($0.entry, $0.memory) }
            spare += ahead.dropFirst(more.count).map { ($0.entry, $0.memory) }
        }

        // New and learning cards short enough pair up in one question, and the
        // room they free goes to the next cards in line.
        var pairs: [Entry] = []
        if pairing >= 4 {
            let short = picked.filter { item in
                let stage = Questions.Stage(item.memory)
                return (stage == .new || stage == .learning) && Questions.isMatchable(item.entry)
            }
            let decks = Dictionary(grouping: short, by: \.entry.key.deck)
            if let best = decks.values.max(by: { $0.count < $1.count }), best.count >= 4 {
                pairs = distinct(best.map(\.entry)).prefix(pairing).map { $0 }
            }
            if pairs.count >= 4 {
                let paired = Set(pairs.map(\.key))
                picked.removeAll { paired.contains($0.entry.key) }
                picked += spare.prefix(pairs.count - 1)
            } else {
                pairs = []
            }
        }
        picked.shuffle(using: &rng)

        let byDeck = Dictionary(grouping: entries, by: \.key.deck)
        var questions = picked.map { entry, memory in
            Questions.make(entry, memory: memory, siblings: byDeck[entry.key.deck] ?? [], using: &rng)
        }
        if !pairs.isEmpty {
            // Not first: a lesson starts with one card.
            questions.insert(Questions.match(pairs.shuffled(using: &rng)), at: Int.random(in: min(1, questions.count)...questions.count, using: &rng))
        }
        return questions
    }

    /// The entries, without one whose front or back reads like one before it.
    private func distinct(_ entries: [Entry]) -> [Entry] {
        var fronts = Set<String>(), backs = Set<String>()
        return entries.filter {
            fronts.insert(Answer.comparable($0.card.front)).inserted && backs.insert(Answer.comparable($0.card.back)).inserted
        }
    }
}

/// A lesson under way: its questions in order, each answer, and the wrong ones
/// asked once more at the end, and the experience points it earns.
///
/// Only a card's first answer counts for FSRS: a card asked again after a wrong
/// answer is practice, so its grade is nil.
public struct LessonRun: Sendable {
    /// How one card went.
    public struct Result: Sendable, Equatable {
        public var question: Question
        public var key: CardKey
        public var attempt: Attempt
        /// The grade for FSRS; nil for practice.
        public var grade: Grade?
        public var isCorrect: Bool
        public var xp: Int
        /// Part of `xp` for right answers in a row.
        public var bonus: Int
    }

    public private(set) var questions: [Question]
    public private(set) var index = 0
    public private(set) var results: [Result] = []
    /// Right answers in a row, and the most in a row so far.
    public private(set) var combo = 0
    public private(set) var bestCombo = 0
    private var answered = Set<Int>()
    private var rng: SplitMix64

    public init(_ questions: [Question], seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.questions = questions
        rng = SplitMix64(seed: seed)
    }

    public var current: Question? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    /// The current question has its answer and waits for `advance()`.
    public var isAnswered: Bool { answered.contains(index) }
    public var isFinished: Bool { index >= questions.count }

    /// How far along, 0 to 1: questions answered over questions there are, the
    /// ones asked again included.
    public var progress: Double {
        questions.isEmpty ? 1 : Double(answered.count) / Double(questions.count)
    }

    /// Takes the answer to the current question: a result for each card it asks.
    /// A card wrong the first time comes back at the end.
    @discardableResult
    public mutating func answer(_ attempt: Attempt) -> [Result] {
        guard let q = current, !isAnswered else { return [] }
        answered.insert(index)
        let isCorrect = attempt.isCorrect && !attempt.gaveUp
        combo = isCorrect ? combo + 1 : 0
        bestCombo = max(bestCombo, combo)
        let bonus = isCorrect && combo >= Score.comboFrom ? Score.comboBonus : 0

        var made: [Result] = []
        if q.game == .match {
            let backs = q.group.map(\.card.back)
            for entry in q.group {
                let right = !attempt.missed.contains(entry.key)
                made.append(Result(
                    question: q, key: entry.key, attempt: attempt,
                    grade: q.isRetry ? nil : Grading.grade(paired: entry.key, in: attempt),
                    isCorrect: right, xp: right ? Score.pair : 0, bonus: 0
                ))
                // A card paired wrong comes back as a choice among the pairing's backs.
                if !right && !q.isRetry {
                    questions.append(Question(entry: entry, game: .choose, options: backs.shuffled(using: &rng), isRetry: true))
                }
            }
            if bonus > 0 { made[0].xp += bonus; made[0].bonus = bonus }
        } else {
            let xp = isCorrect ? (q.isRetry ? Score.practice : Score.answer) + bonus : 0
            made.append(Result(
                question: q, key: q.key, attempt: attempt, grade: q.isRetry ? nil : Grading.grade(attempt, for: q),
                isCorrect: isCorrect, xp: xp, bonus: bonus
            ))
            if !isCorrect && !q.isRetry { questions.append(q.retry(using: &rng)) }
        }
        results += made
        return made
    }

    public mutating func advance() {
        guard isAnswered else { return }
        index += 1
    }

    /// Puts another question in place of the current one before it is answered,
    /// as when the learner cannot listen just now.
    public mutating func replaceCurrent(_ make: (Question) -> Question) {
        guard let q = current, !isAnswered else { return }
        questions[index] = make(q)
    }

    /// The first answers, the ones that count, one for each card.
    public var graded: [Result] { results.filter { $0.grade != nil } }

    public var correct: Int { graded.count { $0.isCorrect } }

    public var accuracy: Double {
        graded.isEmpty ? 0 : Double(correct) / Double(graded.count)
    }

    /// No first answer wrong.
    public var isPerfect: Bool { !graded.isEmpty && correct == graded.count }

    /// Points for the answers so far.
    public var answerXP: Int { results.reduce(0) { $0 + $1.xp } }

    /// Points for finishing, once it is finished.
    public var finishXP: Int { isFinished ? Score.finished + (isPerfect ? Score.perfect : 0) : 0 }

    public var xp: Int { answerXP + finishXP }
}
