import Foundation

/// A card to study, with its deck.
public struct Entry: Sendable, Equatable {
    public var key: CardKey
    public var card: Card
    public var deck: DeckInfo
    /// When the library first had it: new cards come in this order.
    public var firstSeen: Date

    public init(key: CardKey, card: Card, deck: DeckInfo, firstSeen: Date = .distantPast) {
        self.key = key
        self.card = card
        self.deck = deck
        self.firstSeen = firstSeen
    }

    /// Whether its answer is written with spaces between words, which typing and
    /// tiles go by: from the deck's language, or for a deck without one, the answer.
    public var isSpaced: Bool {
        Language.isSpaced(deck.lang?.target, text: card.back)
    }
}

extension Library {
    /// The cards to study, not deleted, those the library had first first.
    public func entries(deck id: String? = nil) -> [Entry] {
        decks.values
            .filter { id == nil || $0.info.id == id }
            .flatMap { deck in
                deck.cards.values
                    .filter { !$0.card.isDeleted }
                    .map { Entry(key: CardKey(deck: deck.info.id, card: $0.card.id), card: $0.card, deck: deck.info, firstSeen: $0.firstSeen) }
            }
            .sorted { ($0.firstSeen, $0.key.deck, $0.key.card) < ($1.firstSeen, $1.key.deck, $1.key.card) }
    }
}

public enum Language {
    /// Written without spaces between words.
    static let unspaced: Set<String> = ["ja", "zh", "yue", "th", "lo", "km", "my", "bo"]

    public static func isSpaced(_ code: String?, text: String) -> Bool {
        if let code, let base = code.lowercased().split(separator: "-").first {
            return !unspaced.contains(String(base))
        }
        return !text.unicodeScalars.contains { s in
            (0x3040...0x30FF).contains(s.value) || (0x3400...0x9FFF).contains(s.value) || (0x0E00...0x0E7F).contains(s.value)
        }
    }

    /// The language's name in Chinese, as the prompts say it: 英语, 日语.
    public static func name(_ code: String?) -> String? {
        guard let code else { return nil }
        return Locale(identifier: "zh-Hans").localizedString(forLanguageCode: code)
    }
}

/// A card as one question of a lesson: the game it is asked in, and what that
/// game needs.
public struct Question: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var entry: Entry
    public var game: Game
    /// 选一选, and 听一听 by meaning: the answer and the wrong ones, shuffled.
    public var options: [String]
    /// 拼一拼 and 听一听: the answer's tiles and a few more, shuffled.
    public var tiles: [Tile]
    /// How many of the tiles make the answer.
    public var answerTiles: Int
    /// 配一配: the cards to pair, this one first.
    public var group: [Entry]
    /// 填一填: the example sentence around the gap.
    public var cloze: Cloze?
    /// Asked again at the end of the lesson after a wrong answer: practice, not a review.
    public var isRetry: Bool

    public init(
        id: UUID = UUID(), entry: Entry, game: Game, options: [String] = [], tiles: [Tile] = [], answerTiles: Int = 0,
        group: [Entry] = [], cloze: Cloze? = nil, isRetry: Bool = false
    ) {
        self.id = id
        self.entry = entry
        self.game = game
        self.options = options
        self.tiles = tiles
        self.answerTiles = answerTiles
        self.group = group
        self.cloze = cloze
        self.isRetry = isRetry
    }

    public var key: CardKey { entry.key }
    public var card: Card { entry.card }
    public var isSpaced: Bool { entry.isSpaced }
    /// The language learnt, when the deck says.
    public var language: String? { entry.deck.lang?.target }

    /// The cards it asks: one, or a pairing's five.
    public var keys: [CardKey] { game == .match ? group.map(\.key) : [key] }

    /// Listening for the meaning picks the front among fronts; everything else
    /// gives the back.
    public var isByMeaning: Bool { game == .listen && tiles.isEmpty }
    public var answer: String { isByMeaning ? card.front : card.back }
    public var cap: Grade { isByMeaning ? .hard : game.cap }

    /// The question with nothing to hear: a heard sentence is put together from
    /// the same tiles, read; a heard word is turned over.
    public func withoutSound() -> Question {
        guard game == .listen else { return self }
        return tiles.isEmpty
            ? Question(entry: entry, game: .flip, isRetry: isRetry)
            : Question(entry: entry, game: .build, tiles: tiles, answerTiles: answerTiles, isRetry: isRetry)
    }

    /// The same question once more, shuffled again.
    public func retry<R: RandomNumberGenerator>(using rng: inout R) -> Question {
        var q = self
        q.id = UUID()
        q.isRetry = true
        q.options.shuffle(using: &rng)
        q.tiles.shuffle(using: &rng)
        return q
    }
}

/// An example sentence with a gap where the answer goes.
public struct Cloze: Sendable, Equatable {
    public var before: String
    public var after: String

    public init(before: String, after: String) {
        self.before = before
        self.after = after
    }
}

/// Making a question of a card.
public enum Questions {
    /// How well a card is known, which decides the game: the better known, the harder.
    public enum Stage: Sendable, Equatable {
        case new, learning, familiar, known

        public init(_ memory: Memory?) {
            guard let m = memory else { self = .new; return }
            if m.phase != .review || m.stability < 3 { self = .learning; return }
            self = m.stability < 21 ? .familiar : .known
        }
    }

    /// The games for each stage, and how often each comes up among those a card can be asked in.
    static func weights(_ stage: Stage) -> [(Game, Int)] {
        switch stage {
        case .new: [(.choose, 1)]
        case .learning: [(.build, 3), (.listen, 2), (.cloze, 2), (.choose, 1)]
        case .familiar: [(.type, 3), (.fix, 3), (.cloze, 2), (.build, 2), (.listen, 2)]
        case .known: [(.type, 4), (.fix, 4), (.cloze, 2), (.listen, 1), (.build, 1)]
        }
    }

    /// A question of `entry`, in a game picked for how well it is known among
    /// those its fields allow. `siblings` are the cards of its deck, for wrong
    /// answers and for pairing.
    public static func make<R: RandomNumberGenerator>(
        _ entry: Entry, memory: Memory?, siblings: [Entry], using rng: inout R, game forced: Game? = nil
    ) -> Question {
        let options = options(for: entry, siblings: siblings, using: &rng)
        let bank = bank(for: entry, siblings: siblings, using: &rng)
        let gap = cloze(for: entry)
        let typeable = isTypeable(entry)
        var ready: Set<Game> = [.flip]
        if options != nil { ready.insert(.choose) }
        if bank != nil { ready.insert(.build) }
        if typeable { ready.insert(.type) }
        if gap != nil && typeable { ready.insert(.cloze) }
        if entry.card.kind == .fix && typeable && Answer.comparable(entry.card.front) != Answer.comparable(entry.card.back) {
            ready.insert(.fix)
        }
        var meanings: [String]?
        if entry.deck.lang?.target != nil {
            meanings = bank == nil ? Self.options(for: entry, siblings: siblings, side: \.front, using: &rng) : nil
            if bank != nil || meanings != nil { ready.insert(.listen) }
        }
        let pairs = isMatchable(entry) ? partners(for: entry, siblings: siblings) : []
        if pairs.count >= 3 { ready.insert(.match) }

        let game = forced.flatMap { ready.contains($0) ? $0 : nil }
            ?? pick(weights(Stage(memory)), from: ready, using: &rng)
            ?? [Game.choose, .build, .type].first { ready.contains($0) }
            ?? .flip
        switch game {
        case .choose:
            return Question(entry: entry, game: game, options: options ?? [])
        case .build:
            return Question(entry: entry, game: game, tiles: bank?.tiles ?? [], answerTiles: bank?.answer ?? 0)
        case .listen:
            return Question(entry: entry, game: game, options: meanings ?? [], tiles: bank?.tiles ?? [], answerTiles: bank?.answer ?? 0)
        case .cloze:
            return Question(entry: entry, game: game, cloze: gap)
        case .match:
            return Question(entry: entry, game: game, group: [entry] + pairs.prefix(4))
        case .type, .fix, .flip:
            return Question(entry: entry, game: game)
        }
    }

    /// Five cards to pair, the first of them `entries[0]`.
    public static func match(_ entries: [Entry]) -> Question {
        Question(entry: entries[0], game: .match, group: entries)
    }

    static func pick<R: RandomNumberGenerator>(_ weights: [(Game, Int)], from ready: Set<Game>, using rng: inout R) -> Game? {
        let open = weights.filter { ready.contains($0.0) }
        let total = open.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return nil }
        var n = Int.random(in: 0..<total, using: &rng)
        for (game, weight) in open {
            if n < weight { return game }
            n -= weight
        }
        return nil
    }

    /// Short enough to type: a few words, or a few characters without spaces.
    static func isTypeable(_ entry: Entry) -> Bool {
        let back = entry.card.back
        return entry.isSpaced
            ? Answer.words(back).count <= 6 && back.count <= 40
            : Answer.squash(back).count <= 8
    }

    /// Short on both sides, to fit a column of five; and not a fix card, whose
    /// front is the learner's own wrong words, not a meaning.
    public static func isMatchable(_ entry: Entry) -> Bool {
        entry.card.kind != .fix && entry.card.front.count <= 12 && entry.card.back.count <= 24
    }

    /// Cards of the deck to pair with this one, none reading the same on either side.
    static func partners(for entry: Entry, siblings: [Entry]) -> [Entry] {
        var fronts: Set<String> = [Answer.comparable(entry.card.front)]
        var backs: Set<String> = [Answer.comparable(entry.card.back)]
        return siblings.filter { e in
            e.key != entry.key && isMatchable(e)
                && fronts.insert(Answer.comparable(e.card.front)).inserted
                && backs.insert(Answer.comparable(e.card.back)).inserted
        }
    }

    /// The answer and two or three wrong ones, shuffled; nil without two wrong ones.
    /// The card's own `distractors` first, and for a fix card what the learner
    /// wrote; then answers from its deck of the same kind and about its length.
    /// `side` \.front gives meanings instead.
    static func options<R: RandomNumberGenerator>(
        for entry: Entry, siblings: [Entry], side: KeyPath<Card, String> = \.back, using rng: inout R
    ) -> [String]? {
        let answer = entry.card[keyPath: side]
        var used: Set<String> = [Answer.comparable(answer)]
        var wrong: [String] = []
        func add(_ s: String) {
            let k = Answer.comparable(s)
            guard wrong.count < 3, !k.isEmpty, used.insert(k).inserted else { return }
            wrong.append(s)
        }
        if side == \Card.back {
            if entry.card.kind == .fix { add(entry.card.front) }
            for d in (entry.card.distractors ?? []).shuffled(using: &rng) { add(d) }
        }
        let others = siblings.filter { $0.key != entry.key }
        for sameKind in [true, false] where wrong.count < 3 {
            let near = others
                .filter { ($0.card.kind == entry.card.kind) == sameKind }
                .sorted {
                    (abs($0.card[keyPath: side].count - answer.count), $0.key.card) < (abs($1.card[keyPath: side].count - answer.count), $1.key.card)
                }
                .prefix(8)
                .shuffled(using: &rng)
            for e in near { add(e.card[keyPath: side]) }
        }
        guard wrong.count >= 2 else { return nil }
        return (wrong + [answer]).shuffled(using: &rng)
    }

    /// The answer's tiles and two or three tiles from other answers of its deck
    /// that are not in it, shuffled; nil when the answer cannot be cut.
    static func bank<R: RandomNumberGenerator>(for entry: Entry, siblings: [Entry], using rng: inout R) -> (tiles: [Tile], answer: Int)? {
        let language = entry.deck.lang?.target
        guard let pieces = Tiles.cut(entry.card, spaced: entry.isSpaced, language: language) else { return nil }
        let others = siblings.filter { $0.key != entry.key }
        var extra: [String] = []
        if entry.isSpaced {
            let inAnswer = Set(Answer.words(entry.card.back))
            var seen = Set<String>()
            let pool = others.flatMap { Tiles.shown($0.card.back) }.map(sentenceCase).filter { word in
                let k = Answer.comparable(word)
                return word.count >= 2 && !k.isEmpty && !inAnswer.contains(k) && seen.insert(k).inserted
            }
            extra = Array(pool.shuffled(using: &rng).prefix(pieces.count <= 4 ? 2 : 3))
        } else {
            // Cutting is slow next to splitting on spaces: a dozen others are enough.
            let inAnswer = Set(pieces)
            let pool = others.shuffled(using: &rng).prefix(12)
                .flatMap { Tiles.cut($0.card, spaced: false, language: language) ?? [] }
            extra = Array(Set(pool).subtracting(inAnswer).sorted().shuffled(using: &rng).prefix(2))
        }
        let tiles = (pieces + extra).enumerated().map { Tile(id: $0.offset, text: $0.element) }
        return (tiles.shuffled(using: &rng), pieces.count)
    }

    /// The card's example with a gap where its answer is; nil without an example
    /// that holds the answer and more.
    public static func cloze(for entry: Entry) -> Cloze? {
        guard let example = entry.card.example else { return nil }
        let text = Answer.straighten(example)
        let answer = Answer.straighten(entry.card.back).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !answer.isEmpty, let range = text.range(of: answer, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let gap = Cloze(before: String(text[..<range.lowerBound]), after: String(text[range.upperBound...]))
        let rest = (gap.before + gap.after).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return rest.isEmpty ? nil : gap
    }

    /// A word taken from the start of another sentence, without the capital that
    /// would give it away: "Merge" → "merge", but "YouTube" and "I" stay.
    static func sentenceCase(_ word: String) -> String {
        guard word != "I", let first = word.first, first.isUppercase,
              word.dropFirst().allSatisfy({ !$0.isUppercase })
        else { return word }
        return word.lowercased()
    }
}
