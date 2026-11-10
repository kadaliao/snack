import SnackKit
import SwiftUI

/// The decks that come with the app, each with a button to add it.
struct StarterList: View {
    let inbox: Inbox

    var body: some View {
        ForEach(inbox.starters) { starter in
            let deck = starter.file.deck
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(deck.title).font(.headline)
                    if let description = deck.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(starter.file.cards.count) 张").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if inbox.isAdded(starter) {
                    Label("已添加", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.right)
                } else {
                    Button("添加") { withAnimation { inbox.add(starter) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.snack)
                        .accessibilityLabel("添加\(deck.title)")
                }
            }
            .padding(.vertical, 4)
        }
    }
}
