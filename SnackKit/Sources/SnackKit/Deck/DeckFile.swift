import Foundation

/// One `*.deck.json` file of the Inbox: a whole deck as its producer last wrote it
/// (spec/deck-format.md).
public struct DeckFile: Sendable, Equatable {
    public static let format = "deck/1"

    public var deck: DeckInfo
    public var cards: [Card]
    /// Cards the file holds that could not be read, so a producer's mistake costs
    /// those cards and not the deck.
    public var skipped: Int

    public init(deck: DeckInfo, cards: [Card], skipped: Int = 0) {
        self.deck = deck
        self.cards = cards
        self.skipped = skipped
    }

    public enum ReadError: Error, Equatable {
        case notJSON
        case wrongFormat(String?)
        case noDeck
    }

    /// Reads a file's bytes. A card it cannot read is skipped; a file that is not
    /// deck/1, or has no deck, is refused.
    public static func read(_ data: Data) throws(ReadError) -> DeckFile {
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw .notJSON
        }
        guard raw.format == format else { throw .wrongFormat(raw.format) }
        guard let deck = raw.deck, !deck.id.isEmpty, !deck.title.isEmpty else { throw .noDeck }
        let cards = (raw.cards ?? []).compactMap(\.card)
        var seen = Set<String>()
        // A second card of the same id is the producer's mistake: the first one counts.
        let unique = cards.filter { seen.insert($0.id).inserted }
        return DeckFile(deck: deck, cards: unique, skipped: (raw.cards?.count ?? 0) - unique.count)
    }

    private struct Raw: Decodable {
        var format: String?
        var deck: DeckInfo?
        var cards: [Lenient<Card>]?
    }
}

/// What a file says about its deck.
public struct DeckInfo: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var source: String?
    public var lang: Lang?
    public var description: String?
    public var updatedAt: Date?

    public struct Lang: Codable, Sendable, Equatable {
        /// The language learnt, as a BCP 47 code: "en", "ja".
        public var target: String?
        /// The learner's own.
        public var native: String?

        public init(target: String? = nil, native: String? = nil) {
            self.target = target
            self.native = native
        }
    }

    public init(id: String, title: String, source: String? = nil, lang: Lang? = nil, description: String? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.source = source
        self.lang = lang
        self.description = description
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        lang = try? c.decodeIfPresent(Lang.self, forKey: .lang)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        updatedAt = c.isoDate(.updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(lang, forKey: .lang)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(updatedAt.map(ISODate.string), forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, source, lang, description, updatedAt
    }
}

/// One card, as its producer wrote it.
public struct Card: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// An expression: the learner's language on the front, the one learnt on the back.
        case phrase
        /// A whole sentence and the frame it can be reused in.
        case pattern
        /// What the learner wrote, and the better way to say it.
        case fix
        /// Any question and its answer.
        case qa
    }

    public var id: String
    public var kind: Kind
    public var front: String
    public var back: String
    public var reading: String?
    public var context: String?
    public var example: String?
    public var why: String?
    public var pattern: String?
    public var distractors: [String]?
    public var tiles: [String]?
    public var tags: [String]?
    public var seen: Int?
    public var addedAt: Date?
    public var deleted: Bool?

    public init(
        id: String, kind: Kind, front: String, back: String,
        reading: String? = nil, context: String? = nil, example: String? = nil, why: String? = nil,
        pattern: String? = nil, distractors: [String]? = nil, tiles: [String]? = nil, tags: [String]? = nil,
        seen: Int? = nil, addedAt: Date? = nil, deleted: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.front = front
        self.back = back
        self.reading = reading
        self.context = context
        self.example = example
        self.why = why
        self.pattern = pattern
        self.distractors = distractors
        self.tiles = tiles
        self.tags = tags
        self.seen = seen
        self.addedAt = addedAt
        self.deleted = deleted
    }

    public var isDeleted: Bool { deleted == true }

    /// Reads a card; the four fields every card has must be there and not empty.
    /// An optional field of the wrong type is left out rather than losing the card.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        front = try c.decode(String.self, forKey: .front)
        back = try c.decode(String.self, forKey: .back)
        let blank = [id, front, back].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "an empty id, front or back"))
        }
        reading = try? c.decodeIfPresent(String.self, forKey: .reading)
        context = try? c.decodeIfPresent(String.self, forKey: .context)
        example = try? c.decodeIfPresent(String.self, forKey: .example)
        why = try? c.decodeIfPresent(String.self, forKey: .why)
        pattern = try? c.decodeIfPresent(String.self, forKey: .pattern)
        distractors = try? c.decodeIfPresent([String].self, forKey: .distractors)
        tiles = try? c.decodeIfPresent([String].self, forKey: .tiles)
        tags = try? c.decodeIfPresent([String].self, forKey: .tags)
        seen = try? c.decodeIfPresent(Int.self, forKey: .seen)
        addedAt = c.isoDate(.addedAt)
        deleted = try? c.decodeIfPresent(Bool.self, forKey: .deleted)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(front, forKey: .front)
        try c.encode(back, forKey: .back)
        try c.encodeIfPresent(reading, forKey: .reading)
        try c.encodeIfPresent(context, forKey: .context)
        try c.encodeIfPresent(example, forKey: .example)
        try c.encodeIfPresent(why, forKey: .why)
        try c.encodeIfPresent(pattern, forKey: .pattern)
        try c.encodeIfPresent(distractors, forKey: .distractors)
        try c.encodeIfPresent(tiles, forKey: .tiles)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(seen, forKey: .seen)
        try c.encodeIfPresent(addedAt.map(ISODate.string), forKey: .addedAt)
        try c.encodeIfPresent(deleted, forKey: .deleted)
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, front, back, reading, context, example, why, pattern, distractors, tiles, tags, seen, addedAt, deleted
    }
}

/// A value that may fail to decode, so one bad element does not fail its array.
struct Lenient<Value: Decodable>: Decodable {
    let card: Value?

    init(from decoder: Decoder) throws {
        card = try? Value(from: decoder)
    }
}

/// ISO 8601 times, with or without fractions of a second ("2026-11-10T08:00:00.123Z",
/// as JavaScript's `toISOString` writes them).
enum ISODate {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func parse(_ s: String) -> Date? {
        if let d = try? fractional.parse(s) { return d }
        return try? Date.ISO8601FormatStyle().parse(s)
    }

    static func string(_ d: Date) -> String {
        fractional.format(d)
    }
}

extension KeyedDecodingContainer {
    /// A time written as ISO 8601 text; nil when it is missing or unreadable.
    func isoDate(_ key: Key) -> Date? {
        guard let s = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return ISODate.parse(s)
    }
}
