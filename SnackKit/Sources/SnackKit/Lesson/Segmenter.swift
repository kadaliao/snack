import Foundation
import NaturalLanguage

/// Cutting a sentence written without spaces into tiles.
enum Segmenter {
    static let most = 8
    /// Shorter than this and it is a word or two, nothing to put together: 何名様
    /// would come apart into 何 / 名 / 様.
    static let least = 7

    /// Japanese or Chinese cut into words: in Japanese each run of hiragana (a
    /// particle, an ending) goes with the word before it, since Apple's tokenizer
    /// cuts finer than a learner thinks ("終わっ / て / から" is "終わってから"); then
    /// the shortest neighbours are joined until there are at most eight. Nil for a
    /// text of a few characters, when that is less than two pieces, or when the
    /// pieces do not make up the text.
    static func pieces(_ text: String, language code: String?) -> [String]? {
        guard Answer.squash(text).count >= least else { return nil }
        let language: NLLanguage = switch code?.lowercased().prefix(2) {
        case "ja": .japanese
        case "zh": .simplifiedChinese
        default: NLLanguageRecognizer.dominantLanguage(for: text) ?? .undetermined
        }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language)
        var tokens = tokenizer.tokens(for: text.startIndex..<text.endIndex).map { String(text[$0]) }
        if language == .japanese {
            tokens = tokens.reduce(into: []) { merged, token in
                if !merged.isEmpty, isHiragana(token) { merged[merged.count - 1] += token } else { merged.append(token) }
            }
        }
        while tokens.count > most {
            let i = (0..<tokens.count - 1).min { tokens[$0].count + tokens[$0 + 1].count < tokens[$1].count + tokens[$1 + 1].count }!
            tokens[i] += tokens.remove(at: i + 1)
        }
        guard tokens.count >= 2, Answer.squash(tokens.joined()) == Answer.squash(text) else { return nil }
        return tokens
    }

    private static func isHiragana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
    }
}
