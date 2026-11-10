import SnackKit
import SwiftUI

/// 拼一拼: put the answer together from tiles, some of which are not in it.
struct BuildView: View {
    let question: Question
    let isLocked: Bool
    let onAnswer: (Attempt) -> Void

    @State private var shown = Date.now
    @State private var placed: [Tile] = []
    @State private var verdict: Bool?

    var body: some View {
        VStack(spacing: 20) {
            // The answer as it is put together, on ruled lines.
            FlowLayout(spacing: 8, lineSpacing: 14) {
                ForEach(placed) { tile in
                    Button { take(tile) } label: { TileLabel(text: tile.text) }
                        .buttonStyle(CardButtonStyle(tone: verdict.map { $0 ? .right : .wrong } ?? .plain, radius: 10))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(alignment: .top) { Lines() }

            FlowLayout(spacing: 8, lineSpacing: 12) {
                ForEach(question.tiles) { tile in
                    let isUsed = placed.contains(tile)
                    Button { put(tile) } label: { TileLabel(text: tile.text).opacity(isUsed ? 0 : 1) }
                        .buttonStyle(CardButtonStyle(tone: isUsed ? .muted : .plain, radius: 10))
                        .disabled(isUsed)
                        .accessibilityIdentifier("tile")
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
            Button("检查", action: check)
                .buttonStyle(ChunkyButtonStyle())
                .disabled(placed.isEmpty || isLocked)
        }
        .sensoryFeedback(.selection, trigger: placed.count)
    }

    private func put(_ tile: Tile) {
        guard !isLocked else { return }
        withAnimation(.snappy(duration: 0.2)) { placed.append(tile) }
    }

    private func take(_ tile: Tile) {
        guard !isLocked else { return }
        withAnimation(.snappy(duration: 0.2)) { placed.removeAll { $0 == tile } }
    }

    private func check() {
        let isRight = Tiles.isRight(placed.map(\.text), answer: question.card.back, spaced: question.isSpaced)
        verdict = isRight
        onAnswer(Attempt(isCorrect: isRight, seconds: Date.now.timeIntervalSince(shown)))
    }
}

private struct TileLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

/// Three ruled lines to write the answer on.
private struct Lines: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                Spacer().frame(height: 51)
                Rectangle().fill(Color(.systemGray5)).frame(height: 1.5)
            }
        }
    }
}
