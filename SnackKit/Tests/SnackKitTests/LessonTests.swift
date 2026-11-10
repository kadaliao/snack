import Foundation
import Testing

@testable import SnackKit

private let t0 = Date(timeIntervalSince1970: 1_794_297_600)  // 2026-11-10T08:00:00Z
private let scheduler = Scheduler()
private let en = DeckInfo(id: "prompt-en.en", title: "英语", lang: .init(target: "en", native: "zh"))

private func entry(_ id: String, _ kind: Card.Kind = .phrase, front: String = "前", back: String, deck: DeckInfo = en, tiles: [String]? = nil, distractors: [String]? = nil, at: Int = 0) -> Entry {
    Entry(
        key: CardKey(deck: deck.id, card: id),
        card: Card(id: id, kind: kind, front: front, back: back, distractors: distractors, tiles: tiles),
        deck: deck,
        firstSeen: t0.addingTimeInterval(Double(at))
    )
}

private let phrases = [
    entry("a", front: "顺便", back: "while you're at it"),
    entry("b", front: "两边", back: "on both sides"),
    entry("c", front: "搞好了", back: "sorted out"),
    entry("d", front: "一个个", back: "one by one"),
    entry("e", front: "跟进一下", back: "follow up on them"),
    entry("f", front: "兜底", back: "fall back to"),
]

// MARK: - Answers

@Test func typedAnswersForgiveCaseAndPunctuationButNotMissingWords() {
    #expect(Answer.check("While you are at it.", against: "while you're at it", spaced: true) == .exact)
    #expect(Answer.check("  sorted   OUT ", against: "sorted out", spaced: true) == .exact)
    #expect(Answer.check("I can't", against: "I cannot", spaced: true) == .exact)
    #expect(Answer.check("on both sieds", against: "on both sides", spaced: true) == .typo)
    #expect(Answer.check("follow up on thme", against: "follow up on them", spaced: true) == .typo)
    #expect(Answer.check("Hold off on comitting untill the tests finish", against: "Hold off on committing until the tests finish.", spaced: true) == .typo)
    #expect(Answer.check("Hold of on committing until the tests finish", against: "Hold off on committing until the tests finish.", spaced: true) == .wrong)
    // A missing article, a wrong preposition: wrong, not a typo.
    #expect(Answer.check("add timeout", against: "add a timeout", spaced: true) == .wrong)
    #expect(Answer.check("respond me", against: "respond to me", spaced: true) == .wrong)
    #expect(Answer.check("follow up in them", against: "follow up on them", spaced: true) == .wrong)
    #expect(Answer.check("on bath sades", against: "on both sides", spaced: true) == .wrong)
    #expect(Answer.check("", against: "sorted out", spaced: true) == .wrong)
    // Without spaces: the characters, a slip allowed in a long enough answer.
    #expect(Answer.check("念のため。", against: "念のため", spaced: false) == .exact)
    #expect(Answer.check("念のだめ", against: "念のため", spaced: false) == .typo)
    #expect(Answer.check("はい", against: "いいえ", spaced: false) == .wrong)
}

@Test func answersAreCutIntoTiles() {
    let short = Card(id: "x", kind: .phrase, front: "两边", back: "On both sides.")
    #expect(Tiles.cut(short, spaced: true) == ["On", "both", "sides"])
    #expect(Tiles.cut(Card(id: "x", kind: .phrase, front: "好", back: "OK"), spaced: true) == nil)
    // Without spaces, only the card's own tiles.
    let ja = Card(id: "j", kind: .pattern, front: "测完再提交", back: "テストが終わってからコミットしてください。", tiles: ["テストが", "終わってから", "コミットして", "ください。"])
    #expect(Tiles.cut(ja, spaced: false)?.count == 4)
    #expect(Tiles.cut(Card(id: "j", kind: .phrase, front: "以防万一", back: "念のため"), spaced: false) == nil)

    // A long sentence comes in pieces of a few words, no more than twelve of them.
    let long = Card(id: "l", kind: .pattern, front: "长", back: "Could we add an option to show all icons (including the ones that aren't hidden) inside the island?")
    let pieces = Tiles.cut(long, spaced: true)!
    #expect(pieces.count <= Tiles.most)
    #expect(Tiles.isRight(pieces, answer: long.back, spaced: true))
}

@Test func tilesThatReadTheSameStandInForEachOther() {
    let answer = "one by one"
    #expect(Tiles.isRight(["one", "by", "one"], answer: answer, spaced: true))
    #expect(!Tiles.isRight(["one", "one", "by"], answer: answer, spaced: true))
    #expect(!Tiles.isRight(["one", "by"], answer: answer, spaced: true))
    // A tile that runs two words together is not the two words.
    #expect(!Tiles.isRight(["follow", "upon", "them"], answer: "follow up on them", spaced: true))
    #expect(Tiles.isRight(["テストが", "終わってから", "コミットして", "ください。"], answer: "テストが終わってからコミットしてください。", spaced: false))
}

// MARK: - Grading

private func question(_ game: Game, back: String = "sorted out", tiles: Int = 2) -> Question {
    Question(entry: entry("c", back: back), game: game, answerTiles: tiles)
}

@Test func gradesComeFromHowItWentCappedByTheGame() {
    let typed = question(.type)
    #expect(Grading.grade(Attempt(isCorrect: true, seconds: 3), for: typed) == .easy)
    #expect(Grading.grade(Attempt(isCorrect: true, hasTypo: true, seconds: 3), for: typed) == .good)
    #expect(Grading.grade(Attempt(isCorrect: true, seconds: 12), for: typed) == .good)
    #expect(Grading.grade(Attempt(isCorrect: true, seconds: 60), for: typed) == .hard)
    #expect(Grading.grade(Attempt(isCorrect: true, usedHint: true, seconds: 3), for: typed) == .hard)
    #expect(Grading.grade(Attempt(isCorrect: false, seconds: 3), for: typed) == .again)
    #expect(Grading.grade(.gaveUp(seconds: 3), for: typed) == .again)

    // One right in four by chance: a choice earns Hard at most.
    #expect(Grading.grade(Attempt(isCorrect: true, seconds: 1), for: question(.choose)) == .hard)
    #expect(Grading.grade(Attempt(isCorrect: true, seconds: 2), for: question(.build)) == .good)
    #expect(Grading.grade(Attempt(isCorrect: true, seconds: 30), for: question(.build)) == .hard)
    // A flipped card is graded by the learner, up to Good.
    #expect(Grading.grade(.flipped(.easy, seconds: 2), for: question(.flip)) == .good)
    #expect(Grading.grade(.flipped(.again, seconds: 2), for: question(.flip)) == .again)
}

// MARK: - Questions

@Test func theBetterACardIsKnownTheHarderTheGame() {
    var rng = SplitMix64(seed: 1)
    let card = phrases[1]
    #expect(Questions.make(card, memory: nil, siblings: phrases, using: &rng).game == .choose)

    var known = scheduler.review(nil, .easy, at: t0)
    known.stability = 60
    for _ in 0..<5 {
        #expect(Questions.make(card, memory: known, siblings: phrases, using: &rng).game == .type)
    }
    // Too long to type: put together from tiles.
    let sentence = entry("p", .pattern, back: "Hold off on committing until the tests finish.")
    #expect(Questions.make(sentence, memory: known, siblings: phrases, using: &rng).game == .build)
    // A long answer with nothing to choose from or build: turned over.
    let qa = DeckInfo(id: "sd", title: "系统设计")
    let long = entry("q", .qa, front: "什么是 CAP？", back: "一致性、可用性、分区容错性，三者最多同时满足两个", deck: qa)
    #expect(Questions.make(long, memory: known, siblings: [long], using: &rng).game == .flip)
    #expect(Questions.make(long, memory: nil, siblings: [long], using: &rng).game == .flip)
}

@Test func choicesAreDistinctAndHoldTheAnswer() {
    var rng = SplitMix64(seed: 7)
    for e in phrases {
        let q = Questions.make(e, memory: nil, siblings: phrases, using: &rng, game: .choose)
        #expect(q.game == .choose)
        #expect(q.options.count == 4)
        #expect(q.options.contains(e.card.back))
        #expect(Set(q.options.map(Answer.comparable)).count == 4)
    }
    // A fix card offers what the learner wrote as a wrong answer.
    let fix = entry("x", .fix, front: "add timeout", back: "add a timeout")
    let q = Questions.make(fix, memory: nil, siblings: phrases + [fix], using: &rng, game: .choose)
    #expect(q.options.contains("add timeout"))
    // The card's own wrong answers come first.
    let own = entry("o", back: "nit", distractors: ["blocker", "hotfix", "minor bug"])
    #expect(Set(Questions.make(own, memory: nil, siblings: phrases, using: &rng, game: .choose).options) == ["nit", "blocker", "hotfix", "minor bug"])
}

@Test func theTilesAreTheAnswersAndAFewThatAreNot() {
    var rng = SplitMix64(seed: 3)
    let e = phrases[4]
    let q = Questions.make(e, memory: nil, siblings: phrases, using: &rng, game: .build)
    #expect(q.game == .build)
    #expect(q.answerTiles == 4)
    #expect(q.tiles.count == 6)
    #expect(Set(q.tiles.map(\.id)).count == 6)
    let extra = q.tiles.filter { $0.id >= 4 }.map(\.text)
    #expect(extra.allSatisfy { !["follow", "up", "on", "them"].contains($0.lowercased()) })
    #expect(Tiles.isRight(q.tiles.sorted { $0.id < $1.id }.prefix(4).map(\.text), answer: e.card.back, spaced: true))
    #expect(Questions.sentenceCase("Merge") == "merge")
    #expect(Questions.sentenceCase("YouTube") == "YouTube")
    #expect(Questions.sentenceCase("I") == "I")
}

// MARK: - Planning

private func many(_ n: Int) -> [Entry] {
    (0..<n).map { entry("c\($0)", front: "词\($0)", back: "word number \($0)", at: $0) }
}

@Test func aLessonIsDueCardsFirstWithAFewNewOnes() {
    let cards = many(30)
    var reviews: [Review] = []
    // Twelve cards learnt a week ago, now due; three more learnt today, not due.
    for e in cards[0..<12] { reviews.append(Review(card: e.key, grade: .easy, at: t0.addingTimeInterval(-30 * 86_400))) }
    for e in cards[12..<15] { reviews.append(Review(card: e.key, grade: .easy, at: t0.addingTimeInterval(-60))) }
    let progress = Progress(reviews, scheduler: scheduler)
    let planner = Planner()
    var rng = SplitMix64(seed: 5)

    let q = planner.plan(cards, progress: progress, scheduler: scheduler, now: t0, timeZone: .gmt, newLeft: 10, using: &rng)
    #expect(q.count == 10)
    let keys = Set(q.map(\.key.card))
    #expect(keys.filter { progress.memories[CardKey(deck: en.id, card: $0)] == nil }.count == 2)
    #expect(keys.isSubset(of: Set(cards[0..<12].map(\.key.card) + ["c15", "c16"])))

    let outlook = planner.outlook(cards, progress: progress, now: t0, timeZone: .gmt, newLeft: 10)
    #expect(outlook == .init(due: 12, new: 10, unseen: 15, studied: 15))

    // No new cards left today: only those due.
    let dueOnly = planner.plan(cards, progress: progress, scheduler: scheduler, now: t0, timeZone: .gmt, newLeft: 0, using: &rng)
    #expect(dueOnly.count == 10)
    #expect(dueOnly.allSatisfy { progress.memories[$0.key] != nil })
}

@Test func newCardsComeInTheOrderTheyCameAndNoMoreThanLeft() {
    let cards = many(20)
    var rng = SplitMix64(seed: 9)
    let q = Planner().plan(cards, progress: Progress(), scheduler: scheduler, now: t0, newLeft: 3, using: &rng)
    #expect(Set(q.map(\.key.card)) == ["c0", "c1", "c2"])
    #expect(q.allSatisfy { $0.game == .choose })
    #expect(Planner().plan(cards, progress: Progress(), scheduler: scheduler, now: t0, newLeft: 0, using: &rng).isEmpty)
}

@Test func withLittleDueALessonTakesCardsAhead() {
    let cards = many(8)
    // All learnt just now: none due, and no new card left.
    let progress = Progress(cards.map { Review(card: $0.key, grade: .easy, at: t0.addingTimeInterval(-60)) }, scheduler: scheduler)
    var rng = SplitMix64(seed: 2)
    let q = Planner().plan(cards, progress: progress, scheduler: scheduler, now: t0, newLeft: 0, using: &rng)
    #expect(q.count == 8)

    // A card in learning, due in ten minutes, counts as due a little before.
    let learning = Progress([Review(card: cards[0].key, grade: .good, at: t0)], scheduler: scheduler)
    let planner = Planner(learnAhead: 5 * 60)
    #expect(planner.outlook(cards, progress: learning, now: t0, newLeft: 0).due == 0)
    #expect(planner.outlook(cards, progress: learning, now: t0.addingTimeInterval(6 * 60), newLeft: 0).due == 1)
    #expect(Planner().outlook(cards, progress: learning, now: t0, newLeft: 0).due == 1)
}

@Test func libraryEntriesSkipDeletedCardsAndComeInOrder() {
    var library = Library()
    let file = DeckFile(deck: en, cards: [
        Card(id: "b", kind: .phrase, front: "两边", back: "on both sides", addedAt: t0.addingTimeInterval(10)),
        Card(id: "a", kind: .phrase, front: "顺便", back: "while you're at it", addedAt: t0),
        Card(id: "z", kind: .phrase, front: "删", back: "gone", deleted: true),
    ])
    library.merge([Library.Source(name: "f.deck.json", file: file)], now: t0)
    #expect(library.entries().map(\.key.card) == ["a", "b"])
    #expect(library.entries(deck: "other").isEmpty)
}

// MARK: - A lesson

@Test func aWrongAnswerComesBackAtTheEndAsPractice() {
    let qs = phrases.prefix(3).map { Question(entry: $0, game: .flip) }
    var run = LessonRun(Array(qs), seed: 1)
    #expect(run.current?.key == qs[0].key)

    let first = run.answer(.flipped(.good, seconds: 2))
    #expect(first?.grade == .good)
    #expect(run.answer(.flipped(.again, seconds: 2)) == nil)  // answered already
    run.advance()

    let wrong = run.answer(.flipped(.again, seconds: 2))
    #expect(wrong?.grade == .again)
    #expect(run.combo == 0)
    #expect(run.questions.count == 4)
    run.advance()
    run.answer(.flipped(.hard, seconds: 2))
    run.advance()
    #expect(run.progress == 0.75)

    let retry = run.current
    #expect(retry?.isRetry == true)
    #expect(retry?.key == qs[1].key)
    #expect(run.answer(.flipped(.again, seconds: 2))?.grade == nil)
    run.advance()
    // Wrong again in practice: not asked a third time.
    #expect(run.isFinished)
    #expect(run.questions.count == 4)
    #expect(run.graded.count == 3)
    #expect(run.correct == 2)
    #expect(run.bestCombo == 1)
}
