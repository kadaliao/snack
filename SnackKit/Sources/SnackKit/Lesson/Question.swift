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
    /// 选一选: the answer and the wrong ones, shuffled.
    public var options: [String]
    /// 拼一拼: the answer's tiles and a few more, shuffled.
    public var tiles: [Tile]
    /// How many of the tiles make the answer.
    public var answerTiles: Int
    /// Asked again at the end of the lesson after a wrong answer: practice, not a review.
    public var isRetry: Bool

    public init(id: UUID = UUID(), entry: Entry, game: Game, options: [String] = [], tiles: [Tile] = [], answerTiles: Int = 0, isRetry: Bool = false) {
        self.id = id
        self.entry = entry
        self.game = game
        self.options = options
        self.tiles = tiles
        self.answerTiles = answerTiles
        self.isRetry = isRetry
    }

    public var key: CardKey { entry.key }
    public var card: Card { entry.card }
    public var isSpaced: Bool { entry.isSpaced }

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

    /// A question of `entry`, in the hardest game it is ready for that its fields
    /// allow, now and then an easier one for a change. `siblings` are the cards of
    /// its deck, for wrong answers.
    public static func make<R: RandomNumberGenerator>(
        _ entry: Entry, memory: Memory?, siblings: [Entry], using rng: inout R, game forced: Game? = nil
    ) -> Question {
        let options = options(for: entry, siblings: siblings, using: &rng)
        let bank = bank(for: entry, siblings: siblings, using: &rng)
        var ready: Set<Game> = [.flip]
        if options != nil { ready.insert(.choose) }
        if bank != nil { ready.insert(.build) }
        if isTypeable(entry) { ready.insert(.type) }

        let order: [Game] = switch Stage(memory) {
        case .new:
            [.choose, .build, .flip]
        case .learning:
            Int.random(in: 0..<4, using: &rng) == 0 ? [.choose, .build, .type, .flip] : [.build, .choose, .type, .flip]
        case .familiar:
            Bool.random(using: &rng) ? [.type, .build, .flip, .choose] : [.build, .type, .flip, .choose]
        case .known:
            [.type, .build, .flip, .choose]
        }
        let game = forced.flatMap { ready.contains($0) ? $0 : nil } ?? order.first { ready.contains($0) } ?? .flip
        return Question(
            entry: entry,
            game: game,
            options: game == .choose ? options ?? [] : [],
            tiles: game == .build ? bank?.tiles ?? [] : [],
            answerTiles: bank?.answer ?? 0
        )
    }

    /// Short enough to type: a few words, or a few characters without spaces.
    static func isTypeable(_ entry: Entry) -> Bool {
        let back = entry.card.back
        return entry.isSpaced
            ? Answer.words(back).count <= 6 && back.count <= 40
            : Answer.squash(back).count <= 8
    }

    /// The answer and two or three wrong ones, shuffled; nil without two wrong ones.
    /// The card's own `distractors` first, and for a fix card what the learner
    /// wrote; then answers from its deck of the same kind and about its length.
    static func options<R: RandomNumberGenerator>(for entry: Entry, siblings: [Entry], using rng: inout R) -> [String]? {
        let answer = entry.card.back
        var used: Set<String> = [Answer.comparable(answer)]
        var wrong: [String] = []
        func add(_ s: String) {
            let k = Answer.comparable(s)
            guard wrong.count < 3, !k.isEmpty, used.insert(k).inserted else { return }
            wrong.append(s)
        }
        if entry.card.kind == .fix { add(entry.card.front) }
        for d in (entry.card.distractors ?? []).shuffled(using: &rng) { add(d) }
        let others = siblings.filter { $0.key != entry.key }
        for sameKind in [true, false] where wrong.count < 3 {
            let near = others
                .filter { ($0.card.kind == entry.card.kind) == sameKind }
                .sorted { (abs($0.card.back.count - answer.count), $0.key.card) < (abs($1.card.back.count - answer.count), $1.key.card) }
                .prefix(8)
                .shuffled(using: &rng)
            for e in near { add(e.card.back) }
        }
        guard wrong.count >= 2 else { return nil }
        return (wrong + [answer]).shuffled(using: &rng)
    }

    /// The answer's tiles and two or three tiles from other answers of its deck
    /// that are not in it, shuffled; nil when the answer cannot be cut.
    static func bank<R: RandomNumberGenerator>(for entry: Entry, siblings: [Entry], using rng: inout R) -> (tiles: [Tile], answer: Int)? {
        guard let pieces = Tiles.cut(entry.card, spaced: entry.isSpaced) else { return nil }
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
            let inAnswer = Set(pieces)
            let pool = Set(others.flatMap { $0.card.tiles ?? [] }).subtracting(inAnswer).sorted()
            extra = Array(pool.shuffled(using: &rng).prefix(2))
        }
        let tiles = (pieces + extra).enumerated().map { Tile(id: $0.offset, text: $0.element) }
        return (tiles.shuffled(using: &rng), pieces.count)
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
