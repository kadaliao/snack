import SnackKit
import SwiftUI

/// 翻一翻: think of the answer, turn the card over, and say how it went.
struct FlipView: View {
    let question: Question
    let onAnswer: (Attempt) -> Void

    @State private var shown = Date.now
    @State private var isTurned = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                face(isBack: false) {
                    VStack(spacing: 10) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.snack)
                        Text("先在心里想一想答案")
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(isTurned ? 0 : 1)
                face(isBack: true) {
                    AnswerDetails(card: question.card, showsAnswer: true)
                }
                .rotation3DEffect(.degrees(180), axis: (0, 1, 0))
                .opacity(isTurned ? 1 : 0)
            }
            .rotation3DEffect(.degrees(isTurned ? 180 : 0), axis: (0, 1, 0))
            .animation(.spring(duration: 0.5), value: isTurned)

            Spacer(minLength: 0)
            if isTurned {
                HStack(spacing: 10) {
                    grade("忘了", .again, .wrong)
                    grade("有点难", .hard, .orange)
                    grade("记得", .good, .right)
                }
            } else {
                Button("翻过来") { isTurned = true }
                    .buttonStyle(ChunkyButtonStyle())
            }
        }
    }

    private func face<Content: View>(isBack: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
    }

    private func grade(_ title: String, _ grade: Grade, _ color: Color) -> some View {
        Button(title) {
            onAnswer(.flipped(grade, seconds: Date.now.timeIntervalSince(shown)))
        }
        .buttonStyle(ChunkyButtonStyle(color: color))
    }
}

/// A card's answer and what goes with it: reading, example, pattern, why.
struct AnswerDetails: View {
    let card: Card
    var showsAnswer = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsAnswer {
                Text(card.back)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reading = card.reading {
                Text(reading).font(.callout).foregroundStyle(.secondary)
            }
            if let why = card.why {
                Label(why, systemImage: "lightbulb").font(.callout)
            }
            if let pattern = card.pattern {
                Label(pattern, systemImage: "text.quote").font(.callout.italic())
            }
            if let example = card.example, Answer.comparable(example) != Answer.comparable(card.back) {
                Text(example)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
