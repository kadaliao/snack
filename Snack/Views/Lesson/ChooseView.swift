import SnackKit
import SwiftUI

/// 选一选: tap the answer among four. Also 听一听 by meaning, and a card paired
/// wrong asked again.
struct ChooseView: View {
    let question: Question
    let isLocked: Bool
    let onAnswer: (Attempt) -> Void

    @State private var shown = Date.now
    @State private var picked: String?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    guard picked == nil, !isLocked else { return }
                    picked = option
                    onAnswer(Attempt(isCorrect: option == question.answer, seconds: Date.now.timeIntervalSince(shown)))
                } label: {
                    Text(option)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .buttonStyle(CardButtonStyle(tone: tone(option)))
                .accessibilityIdentifier("option")
            }
            Spacer(minLength: 0)
        }
    }

    private func tone(_ option: String) -> Tone {
        guard let picked else { return .plain }
        if option == question.answer { return .right }
        return option == picked ? .wrong : .muted
    }
}
