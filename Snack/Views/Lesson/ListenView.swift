import SnackKit
import SwiftUI

/// 听一听: the answer said aloud, to put together from tiles, or when it is too
/// short for tiles, to pick what it means.
struct ListenView: View {
    let question: Question
    let isLocked: Bool
    let onAnswer: (Attempt) -> Void
    /// The learner cannot listen just now.
    let onQuiet: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Button { say(slowly: false) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 34))
                        .frame(width: 96, height: 72)
                }
                .buttonStyle(ChunkyButtonStyle(color: .blue))
                .frame(width: 96)
                Button { say(slowly: true) } label: {
                    Image(systemName: "tortoise.fill")
                        .font(.title2)
                        .frame(width: 64, height: 52)
                }
                .buttonStyle(ChunkyButtonStyle(color: .blue.opacity(0.7)))
                .frame(width: 64)
                .accessibilityLabel("慢一点")
                Spacer()
                Button("现在不方便听", action: onQuiet)
                    .font(.footnote.weight(.semibold))
                    .tint(.secondary)
                    .disabled(isLocked)
            }
            if question.isByMeaning {
                ChooseView(question: question, isLocked: isLocked, onAnswer: onAnswer)
            } else {
                BuildView(question: question, isLocked: isLocked, onAnswer: onAnswer)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            say(slowly: false)
        }
    }

    private func say(slowly: Bool) {
        guard let language = question.language else { return }
        Speaker.shared.say(question.card.back, language: language, slowly: slowly)
    }
}
