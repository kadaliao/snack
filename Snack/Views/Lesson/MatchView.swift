import SnackKit
import SwiftUI

/// 配一配: fronts on the left, backs on the right, tapped in pairs. A front put
/// with the wrong back is missed: that card counts as forgotten.
struct MatchView: View {
    let question: Question
    let onAnswer: (Attempt) -> Void

    @State private var shown = Date.now
    @State private var lefts: [Entry]
    @State private var rights: [Entry]
    @State private var left: CardKey?
    @State private var right: CardKey?
    @State private var paired: Set<CardKey> = []
    @State private var wrongPair: [CardKey] = []
    @State private var missed: Set<CardKey> = []
    @State private var misses = 0

    init(question: Question, onAnswer: @escaping (Attempt) -> Void) {
        self.question = question
        self.onAnswer = onAnswer
        _lefts = State(initialValue: question.group.shuffled())
        _rights = State(initialValue: question.group.shuffled())
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                column(lefts, isLeft: true)
                column(rights, isLeft: false)
            }
            Spacer(minLength: 0)
        }
        .sensoryFeedback(.success, trigger: paired.count)
        .sensoryFeedback(.error, trigger: misses)
    }

    private func column(_ entries: [Entry], isLeft: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(entries, id: \.key) { entry in
                let key = entry.key
                Button { tap(key, isLeft: isLeft) } label: {
                    Text(isLeft ? entry.card.front : entry.card.back)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(CardButtonStyle(tone: tone(key, isLeft: isLeft)))
                .disabled(paired.contains(key))
                .accessibilityIdentifier(isLeft ? "front" : "back")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tone(_ key: CardKey, isLeft: Bool) -> Tone {
        if paired.contains(key) { return .muted }
        if wrongPair.count == 2 && wrongPair[isLeft ? 0 : 1] == key { return .wrong }
        return (isLeft ? left : right) == key ? .picked : .plain
    }

    private func tap(_ key: CardKey, isLeft: Bool) {
        if isLeft { left = left == key ? nil : key } else { right = right == key ? nil : key }
        guard let l = left, let r = right else { return }
        left = nil
        right = nil
        if l == r {
            withAnimation(.snappy) { _ = paired.insert(l) }
            if paired.count == question.group.count {
                onAnswer(.matched(missing: missed, seconds: Date.now.timeIntervalSince(shown)))
            }
        } else {
            missed.insert(l)
            misses += 1
            wrongPair = [l, r]
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if wrongPair == [l, r] { wrongPair = [] }
            }
        }
    }
}
