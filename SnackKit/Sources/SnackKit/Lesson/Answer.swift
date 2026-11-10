import Foundation

/// Comparing what the learner gave with a card's answer.
public enum Answer {
    public enum Verdict: Equatable, Sendable {
        case exact
        /// Right but for a slip of the finger inside a word.
        case typo
        case wrong
    }

    /// Checks a typed answer. In a language written with spaces, case and the
    /// punctuation around words do not count, nor do contractions ("you're" is
    /// "you are"); a slip inside a long enough word is a typo, in one word of every
    /// three. A missing or extra word is wrong, however small: "add timeout" is not
    /// "add a timeout".
    public static func check(_ typed: String, against answer: String, spaced: Bool) -> Verdict {
        guard spaced else {
            let a = squash(typed), b = squash(answer)
            if a == b { return .exact }
            return b.count >= 4 && distance(Array(a), Array(b)) <= 1 ? .typo : .wrong
        }
        let a = words(typed), b = words(answer)
        if a == b { return .exact }
        guard a.count == b.count else { return .wrong }
        var slipped = 0
        for (x, y) in zip(a, b) where x != y {
            if distance(Array(x), Array(y)) > tolerance(y.count) { return .wrong }
            slipped += 1
        }
        return slipped <= max(1, b.count / 3) ? .typo : .wrong
    }

    /// Slips allowed in a word of `n` letters: none in short words, where one
    /// letter makes another word ("a", "an", "on", "in").
    static func tolerance(_ n: Int) -> Int {
        n <= 3 ? 0 : n <= 7 ? 1 : 2
    }

    /// The words of a sentence as they are compared.
    public static func words(_ s: String) -> [String] {
        expand(straighten(s.lowercased()))
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    /// The text without case, spaces or punctuation, for languages written
    /// without spaces.
    public static func squash(_ s: String) -> String {
        String(straighten(s.lowercased()).unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }.map(Character.init))
    }

    /// A text as two answers are told apart by, so options that read the same
    /// count once.
    public static func comparable(_ s: String) -> String {
        words(s).joined(separator: " ")
    }

    private static func straighten(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    private static let contractions: [(String, String)] = [
        ("won't", "will not"), ("can't", "can not"), ("cannot", "can not"), ("shan't", "shall not"),
        ("n't", " not"), ("'re", " are"), ("'m", " am"), ("'ll", " will"), ("'ve", " have"),
    ]

    private static func expand(_ s: String) -> String {
        contractions.reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Edits to turn `a` into `b`: a letter added, dropped, changed, or two side
    /// by side swapped ("thme" is one from "them").
    static func distance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}

/// A piece of the answer to put in place.
public struct Tile: Identifiable, Hashable, Sendable {
    public var id: Int
    public var text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// Cutting an answer into tiles, and telling whether tiles put together make it.
public enum Tiles {
    /// More tiles than this and a sentence is cut into pieces of a few words.
    public static let most = 12

    /// The answer's pieces in order: the card's own `tiles`, or else in a language
    /// written with spaces its words. Nil when it is less than two pieces.
    public static func cut(_ card: Card, spaced: Bool) -> [String]? {
        if let given = card.tiles?.map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }), given.count >= 2 {
            return given
        }
        guard spaced else { return nil }
        let pieces = shown(card.back)
        guard pieces.count >= 2 else { return nil }
        guard pieces.count > most else { return pieces }
        let size = (pieces.count + most - 1) / most
        return stride(from: 0, to: pieces.count, by: size).map {
            pieces[$0..<min($0 + size, pieces.count)].joined(separator: " ")
        }
    }

    /// A sentence's words as tiles show them: as written, without the punctuation around them.
    public static func shown(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    /// Whether the tiles put down make the answer. Only the text counts, so two
    /// tiles that read the same can stand in for each other.
    public static func isRight(_ placed: [String], answer: String, spaced: Bool) -> Bool {
        spaced
            ? Answer.words(placed.joined(separator: " ")) == Answer.words(answer)
            : Answer.squash(placed.joined()) == Answer.squash(answer)
    }
}
