import SnackKit
import SwiftUI

/// What a question asks: the game, what to do, the front, and where it came from.
struct PromptView: View {
    let question: Question

    var body: some View {
        let card = question.card
        VStack(alignment: .leading, spacing: 10) {
            Label(question.game.label, systemImage: question.game.symbol)
                .font(.caption.bold())
                .foregroundStyle(Color.snack)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.snack.opacity(0.12), in: .capsule)
            Text(ask)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            switch question.game {
            case .match, .listen:
                // Nothing to read: the cards are the question, or the sound is.
                EmptyView()
            case .cloze:
                if let gap = question.cloze {
                    (Text(gap.before) + Text("\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}\u{2002}").underline(color: .snack) + Text(gap.after))
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Label(card.front, systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            default:
                Text(card.front)
                    .font(card.front.count > 24 ? .title3.bold() : .title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let context = card.context, context != card.front {
                    Text(highlighted(context, card.front))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ask: String {
        let language = Language.name(question.language)
        switch question.game {
        case .match: return "把意思相同的配成对"
        case .listen: return question.isByMeaning ? "听一听，是什么意思？" : "听一听，把听到的拼出来"
        case .cloze: return "填上空缺的部分"
        case .fix: return "这样说不够地道，改成更好的说法"
        default: break
        }
        return switch question.card.kind {
        case .phrase: language.map { "用\($0)怎么说？" } ?? "怎么说？"
        case .pattern: language.map { "这句用\($0)怎么说？" } ?? "这句怎么说？"
        case .fix: "这样说不够地道，应该怎么说？"
        case .qa: "回答"
        }
    }

    private func highlighted(_ context: String, _ part: String) -> AttributedString {
        var text = AttributedString(context)
        if let range = text.range(of: part) {
            text[range].foregroundColor = .primary
            text[range].font = .callout.bold()
        }
        return text
    }
}
