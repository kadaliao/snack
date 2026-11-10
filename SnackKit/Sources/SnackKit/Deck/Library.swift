import Foundation

/// Where a card stands: its deck and its id in it.
public struct CardKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public var deck: String
    public var card: String

    public init(deck: String, card: String) {
        self.deck = deck
        self.card = card
    }

    /// One string for it, as a review log keeps it.
    public var description: String { "\(deck)#\(card)" }
}

/// Every card the Inbox has ever brought, merged from its files.
///
/// The files belong to their producers and the progress to the app, so the
/// library only ever adds and updates: a card gone from its file stays (prompt-en
/// trims its oldest cards, which must not take them from here), and only a card
/// its file marks `deleted` is hidden.
public struct Library: Codable, Sendable, Equatable {
    public var decks: [String: StoredDeck]

    public init(decks: [String: StoredDeck] = [:]) {
        self.decks = decks
    }

    /// A deck as merged from all its files.
    public struct StoredDeck: Codable, Sendable, Equatable {
        public var info: DeckInfo
        public var cards: [String: StoredCard]
        /// The files it was last read from, by name, and the time each was written.
        public var files: [String: Date?]

        /// Its cards to show, those not deleted, the earliest added first.
        public var visible: [Card] {
            cards.values
                .filter { !$0.card.isDeleted }
                .sorted { ($0.firstSeen, $0.card.id) < ($1.firstSeen, $1.card.id) }
                .map(\.card)
        }
    }

    public struct StoredCard: Codable, Sendable, Equatable {
        public var card: Card
        /// The `updatedAt` of the file this version came from, so an older file
        /// read later does not undo a newer one.
        public var version: Date?
        /// When the library first had it.
        public var firstSeen: Date
        /// The most times a producer has said it saw the card.
        public var maxSeen: Int
    }

    /// A file of the Inbox, read.
    public struct Source: Sendable {
        public var name: String
        public var file: DeckFile

        public init(name: String, file: DeckFile) {
            self.name = name
            self.file = file
        }
    }

    /// What one merge did.
    public struct Change: Sendable, Equatable {
        public var added: [CardKey] = []
        public var updated: [CardKey] = []
        /// Fix cards a producer saw again: the same mistake made again, which
        /// counts as forgetting it.
        public var repeated: [CardKey] = []

        public var isEmpty: Bool { added.isEmpty && updated.isEmpty && repeated.isEmpty }
    }

    /// Merges what the files hold now. Merging the same files again changes nothing.
    @discardableResult
    public mutating func merge(_ sources: [Source], now: Date) -> Change {
        var change = Change()
        // The files each deck is read from are the ones here now.
        for id in decks.keys { decks[id]?.files = [:] }
        // The oldest file first, so where two hold a card the newest has the last word.
        let ordered = sources.sorted {
            ($0.file.deck.updatedAt ?? .distantPast, $0.name) < ($1.file.deck.updatedAt ?? .distantPast, $1.name)
        }
        for source in ordered {
            let info = source.file.deck
            let version = info.updatedAt
            var deck = decks[info.id] ?? StoredDeck(info: info, cards: [:], files: [:])
            if (version ?? .distantPast) >= newest(of: deck) { deck.info = info }
            deck.files[source.name] = version

            for card in source.file.cards {
                let key = CardKey(deck: info.id, card: card.id)
                let seen = card.seen ?? 0
                guard var stored = deck.cards[card.id] else {
                    deck.cards[card.id] = StoredCard(card: card, version: version, firstSeen: card.addedAt ?? now, maxSeen: seen)
                    change.added.append(key)
                    continue
                }
                if card.kind == .fix && seen > stored.maxSeen && stored.maxSeen > 0 { change.repeated.append(key) }
                stored.maxSeen = max(stored.maxSeen, seen)
                if (version ?? .distantPast) >= (stored.version ?? .distantPast) {
                    if stored.card != card { change.updated.append(key) }
                    stored.card = card
                    stored.version = version
                }
                deck.cards[card.id] = stored
            }
            decks[info.id] = deck
        }
        return change
    }

    private func newest(of deck: StoredDeck) -> Date {
        deck.files.values.compactMap { $0 }.max() ?? .distantPast
    }

    /// The decks, by title.
    public var sortedDecks: [StoredDeck] {
        decks.values.sorted { ($0.info.title, $0.info.id) < ($1.info.title, $1.info.id) }
    }
}

extension Library {
    /// Reads the library kept at `url`; an empty one where there is none yet.
    public static func load(from url: URL) throws -> Library {
        guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
        return try JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
    }

    /// Keeps the library at `url`, whole or not at all.
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
