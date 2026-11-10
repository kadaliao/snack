import SnackKit
import SwiftUI

/// A deck's cards, to look through: what M0 can show before there is a game.
struct DeckView: View {
    let deck: Library.StoredDeck

    var body: some View {
        List {
            Section {
                if let description = deck.info.description {
                    Text(description)
                }
                LabeledContent("来源", value: deck.info.source ?? "—")
                if let target = deck.info.lang?.target {
                    LabeledContent("学", value: Locale.current.localizedString(forLanguageCode: target) ?? target)
                }
                LabeledContent("文件", value: deck.files.keys.sorted().joined(separator: "\n"))
            }
            Section("\(deck.visible.count) 张") {
                ForEach(deck.visible) { card in
                    CardRow(card: card)
                }
            }
        }
        .navigationTitle(deck.info.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CardRow: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.kind.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
                Text(card.front)
            }
            Text(card.back)
                .foregroundStyle(.tint)
            if let reading = card.reading {
                Text(reading).font(.caption).foregroundStyle(.secondary)
            }
            if let pattern = card.pattern {
                Text(pattern).font(.caption).foregroundStyle(.secondary)
            }
            if let why = card.why {
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
