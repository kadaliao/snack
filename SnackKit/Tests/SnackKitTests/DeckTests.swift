import Foundation
import Testing

@testable import SnackKit

private let examples = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "spec/examples")

private func file(_ json: String) throws -> DeckFile {
    try DeckFile.read(Data(json.utf8))
}

private func deck(id: String = "prompt-en.en", at time: String? = nil, _ cards: String) -> String {
    let updated = time.map { #", "updatedAt": "\#($0)""# } ?? ""
    return #"{"format": "deck/1", "deck": {"id": "\#(id)", "title": "英语"\#(updated)}, "cards": [\#(cards)]}"#
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func readsTheExamples() throws {
    let en = try DeckFile.read(Data(contentsOf: examples.appending(path: "en-code-review.deck.json")))
    #expect(en.deck.id == "examples.en-code-review")
    #expect(en.deck.lang?.target == "en")
    #expect(en.cards.map(\.kind) == [.phrase, .phrase, .pattern, .qa])
    #expect(en.cards[0].distractors == ["minor bug", "blocker", "hotfix"])
    #expect(en.skipped == 0)

    let ja = try DeckFile.read(Data(contentsOf: examples.appending(path: "ja-basics.deck.json")))
    #expect(ja.cards[0].reading == "ねんのため")
    #expect(ja.cards[1].tiles?.joined() == ja.cards[1].back)
}

/// A card that cannot be read costs that card, not the deck; so does a second one
/// of the same id. An optional field of the wrong type is only left out.
@Test func skipsCardsItCannotRead() throws {
    let f = try file(deck(#"""
        {"id": "a", "kind": "phrase", "front": "顺便", "back": "while you're at it", "seen": "twice"},
        {"id": "b", "kind": "word", "front": "x", "back": "y"},
        {"id": "c", "kind": "qa", "front": " ", "back": "y"},
        {"id": "d", "kind": "qa", "back": "y"},
        {"id": "a", "kind": "qa", "front": "again", "back": "y"},
        "not a card"
        """#))
    #expect(f.cards.map(\.id) == ["a"])
    #expect(f.cards[0].seen == nil)
    #expect(f.skipped == 5)
}

@Test func refusesWhatIsNotADeck() {
    #expect(throws: DeckFile.ReadError.notJSON) { try file("{") }
    #expect(throws: DeckFile.ReadError.wrongFormat("deck/2")) { try file(#"{"format": "deck/2", "deck": {"id": "a", "title": "b"}, "cards": []}"#) }
    #expect(throws: DeckFile.ReadError.noDeck) { try file(#"{"format": "deck/1", "cards": []}"#) }
    #expect(throws: DeckFile.ReadError.noDeck) { try file(#"{"format": "deck/1", "deck": {"id": "", "title": "b"}, "cards": []}"#) }
}

/// Times as JavaScript writes them, with milliseconds, and without.
@Test func readsTimes() throws {
    let f = try file(deck(at: "2026-11-10T08:00:00.123Z", #"{"id": "a", "kind": "qa", "front": "q", "back": "a", "addedAt": "2026-11-09T08:00:00Z"}"#))
    let updated = try #require(f.deck.updatedAt)
    #expect(abs(updated.timeIntervalSince1970 - 1_794_297_600.123) < 0.001)
    #expect(f.cards[0].addedAt == Date(timeIntervalSince1970: 1_794_211_200))
}

@Test func mergesFilesIntoTheLibrary() throws {
    var library = Library()
    let first = try file(deck(at: "2026-11-10T08:00:00Z", #"""
        {"id": "a", "kind": "phrase", "front": "顺便", "back": "while you're at it"},
        {"id": "b", "kind": "phrase", "front": "兜底", "back": "fall back to"}
        """#))
    let change = library.merge([.init(name: "prompt-en.en.m1.deck.json", file: first)], now: now)
    #expect(change.added == [CardKey(deck: "prompt-en.en", card: "a"), CardKey(deck: "prompt-en.en", card: "b")])
    #expect(library.decks["prompt-en.en"]?.visible.count == 2)

    // The same file again changes nothing.
    let before = library
    #expect(library.merge([.init(name: "prompt-en.en.m1.deck.json", file: first)], now: now).isEmpty)
    #expect(library == before)
}

/// A snapshot rewritten without a card keeps it here; only `deleted` hides one.
@Test func keepsCardsGoneFromTheirFile() throws {
    var library = Library()
    library.merge([.init(name: "f", file: try file(deck(at: "2026-11-10T08:00:00Z", #"""
        {"id": "a", "kind": "qa", "front": "q1", "back": "a1"},
        {"id": "b", "kind": "qa", "front": "q2", "back": "a2"}
        """#)))], now: now)
    library.merge([.init(name: "f", file: try file(deck(at: "2026-11-11T08:00:00Z", #"""
        {"id": "b", "kind": "qa", "front": "q2", "back": "a2", "deleted": true}
        """#)))], now: now)
    let deck = try #require(library.decks["prompt-en.en"])
    #expect(deck.cards.count == 2)
    #expect(deck.visible.map(\.id) == ["a"])
}

/// Two Macs write a file each to one deck: their cards merge, a card both have is
/// one card, and the newer file has the last word whichever is read last.
@Test func mergesTwoMachines() throws {
    let older = try file(deck(at: "2026-11-10T08:00:00Z", #"""
        {"id": "a", "kind": "phrase", "front": "顺便", "back": "while you're at it", "example": "old"},
        {"id": "b", "kind": "phrase", "front": "兜底", "back": "fall back to"}
        """#))
    let newer = try file(deck(at: "2026-11-10T09:00:00Z", #"""
        {"id": "a", "kind": "phrase", "front": "顺便", "back": "while you're at it", "example": "new"},
        {"id": "c", "kind": "phrase", "front": "过度设计", "back": "over-engineered"}
        """#))

    var together = Library()
    together.merge([.init(name: "m2", file: newer), .init(name: "m1", file: older)], now: now)
    var oneByOne = Library()
    oneByOne.merge([.init(name: "m2", file: newer)], now: now)
    let change = oneByOne.merge([.init(name: "m2", file: newer), .init(name: "m1", file: older)], now: now)

    for library in [together, oneByOne] {
        let deck = try #require(library.decks["prompt-en.en"])
        #expect(Set(deck.cards.keys) == ["a", "b", "c"])
        #expect(deck.cards["a"]?.card.example == "new")
        #expect(Set(deck.files.keys) == ["m1", "m2"])
    }
    #expect(change.added == [CardKey(deck: "prompt-en.en", card: "b")])
    #expect(change.updated.isEmpty)
}

/// A fix the producer saw again is the same mistake made again; a lower count
/// from a machine that did not see it is not.
@Test func notesAMistakeMadeAgain() throws {
    func fix(_ seen: Int, at time: String) throws -> DeckFile {
        try file(deck(at: time, #"{"id": "f", "kind": "fix", "front": "add timeout", "back": "add a timeout", "seen": \#(seen)}"#))
    }
    var library = Library()
    #expect(library.merge([.init(name: "m1", file: try fix(1, at: "2026-11-10T08:00:00Z"))], now: now).repeated.isEmpty)
    let again = library.merge([.init(name: "m1", file: try fix(2, at: "2026-11-11T08:00:00Z"))], now: now)
    #expect(again.repeated == [CardKey(deck: "prompt-en.en", card: "f")])
    // Another Mac, newer, that saw it once: not a repeat, and not one when the first comes back.
    #expect(library.merge([.init(name: "m2", file: try fix(1, at: "2026-11-12T08:00:00Z"))], now: now).repeated.isEmpty)
    #expect(library.merge([.init(name: "m1", file: try fix(2, at: "2026-11-11T08:00:00Z"))], now: now).repeated.isEmpty)
}

@Test func keepsTheLibraryOnDisk() throws {
    var library = Library()
    library.merge([.init(name: "f", file: try file(deck(at: "2026-11-10T08:00:00.5Z", #"""
        {"id": "a", "kind": "phrase", "front": "念のため", "back": "念のため", "reading": "ねんのため", "addedAt": "2026-11-01T00:00:00Z"}
        """#)))], now: now)
    let url = FileManager.default.temporaryDirectory.appending(path: "snack-\(UUID().uuidString)/content.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try library.save(to: url)
    #expect(try Library.load(from: url) == library)
    #expect(try Library.load(from: url.appending(path: "missing")) == Library())
}
