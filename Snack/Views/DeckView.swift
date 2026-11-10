import SnackKit
import SwiftUI

/// A deck: a lesson of its cards alone, and the cards, each with how well it is known.
struct DeckView: View {
    let deck: Library.StoredDeck
    let library: Library
    let study: Study

    @State private var lesson: LessonSetup?

    var body: some View {
        let cards = deck.visible
        List {
            Section {
                Button("刷一节这个牌组", systemImage: "play.fill") {
                    let questions = study.plan(library.entries(deck: deck.info.id))
                    if !questions.isEmpty { lesson = LessonSetup(questions: questions, deck: deck.info.id) }
                }
                .font(.headline)
                .disabled(cards.isEmpty)
            }
            Section {
                if let description = deck.info.description {
                    Text(description)
                }
                LabeledContent("来源", value: deck.info.source ?? "—")
                if let target = deck.info.lang?.target {
                    LabeledContent("学", value: Language.name(target) ?? target)
                }
                LabeledContent("文件", value: deck.files.keys.sorted().joined(separator: "\n"))
            }
            Section("\(cards.count) 张") {
                ForEach(cards) { card in
                    CardRow(card: card, mastery: study.mastery(CardKey(deck: deck.info.id, card: card.id)))
                }
            }
        }
        .navigationTitle(deck.info.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $lesson) { setup in
            LessonView(setup: setup, study: study)
        }
    }
}

private struct CardRow: View {
    let card: Card
    let mastery: Mastery

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(mastery.color)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(card.kind.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                    Text(card.front)
                    Spacer(minLength: 0)
                    Text(mastery.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        }
        .padding(.vertical, 2)
    }
}
