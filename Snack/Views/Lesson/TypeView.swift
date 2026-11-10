import SnackKit
import SwiftUI

/// 默一默: type the answer. A hint shows each word's first letter; giving up
/// shows the answer.
struct TypeView: View {
    let question: Question
    let isLocked: Bool
    let onAnswer: (Attempt, String) -> Void

    @State private var shown = Date.now
    @State private var text = ""
    @State private var usedHint = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            TextField(placeholder, text: $text)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(question.isSpaced ? .asciiCapable : .default)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(check)
                .disabled(isLocked)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isFocused ? Color.snack : .clear, lineWidth: 2))

            if usedHint {
                Text(hint)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack {
                Button("提示", systemImage: "lightbulb") {
                    withAnimation { usedHint = true }
                }
                .disabled(usedHint || isLocked)
                Spacer()
                Button("不会") {
                    onAnswer(.gaveUp(seconds: elapsed), text)
                }
                .disabled(isLocked)
            }
            .font(.subheadline.weight(.semibold))
            .tint(.secondary)

            Spacer(minLength: 0)
            Button("检查", action: check)
                .buttonStyle(ChunkyButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isLocked)
        }
        .onAppear { isFocused = true }
    }

    private var elapsed: Double { Date.now.timeIntervalSince(shown) }

    private var placeholder: String {
        Language.name(question.entry.deck.lang?.target).map { "用\($0)写出来" } ?? "写出答案"
    }

    /// Each word's first letter, the rest blanks: "w____ y_____ a_ i_".
    private var hint: String {
        let back = question.card.back
        guard question.isSpaced else { return String(back.prefix(1)) + String(repeating: "＿", count: max(0, back.count - 1)) }
        return back.split(separator: " ").map { (word: Substring) -> String in
            word.prefix(1) + String(repeating: "_", count: max(0, word.count - 1))
        }.joined(separator: " ")
    }

    private func check() {
        guard !isLocked, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let verdict = Answer.check(text, against: question.card.back, spaced: question.isSpaced)
        isFocused = false
        onAnswer(Attempt(isCorrect: verdict != .wrong, hasTypo: verdict == .typo, usedHint: usedHint, seconds: elapsed), text)
    }
}
