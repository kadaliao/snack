import SnackKit
import SwiftUI

/// A lesson to start: its questions, and the deck it keeps to, if it keeps to one.
struct LessonSetup: Identifiable {
    let id = UUID()
    var questions: [Question]
    var deck: String?
}

/// How a lesson went, for its last page.
struct LessonEnd {
    var graded: Int
    var correct: Int
    var seconds: Double
    var bestCombo: Int
    /// Cards met for the first time.
    var learned: Int
    /// Cards known better than before.
    var leveledUp: Int
    var streak: Streak
    /// This lesson was the day's first, and the streak grew by it.
    var isStreakNew: Bool
    var lessonsToday: Int
    var goal: Int

    var accuracy: Double { graded == 0 ? 0 : Double(correct) / Double(graded) }
}

/// A lesson from first question to last page. Each first answer is graded and
/// logged at once, so leaving halfway keeps what was answered.
struct LessonView: View {
    let setup: LessonSetup
    let study: Study

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.speak) private var speaks = true

    @State private var run: LessonRun
    @State private var result: LessonRun.Result?
    @State private var typed: String?
    @State private var end: LessonEnd?
    @State private var isQuitting = false
    @State private var started = Date.now
    @State private var before: [CardKey: Mastery]
    @State private var rights = 0
    @State private var wrongs = 0

    init(setup: LessonSetup, study: Study) {
        self.setup = setup
        self.study = study
        _run = State(initialValue: LessonRun(setup.questions))
        _before = State(initialValue: Dictionary(
            setup.questions.map { ($0.key, study.mastery($0.key)) },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    var body: some View {
        Group {
            if let end {
                LessonEndView(end: end) { close() }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                playing
            }
        }
        .sensoryFeedback(.success, trigger: rights)
        .sensoryFeedback(.error, trigger: wrongs)
    }

    private var playing: some View {
        VStack(spacing: 0) {
            topBar
            if let q = run.current {
                VStack(alignment: .leading, spacing: 24) {
                    PromptView(question: q)
                    game(q)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .id(q.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if let result {
                FeedbackPanel(result: result, typed: typed, onSpeak: speaker(for: result.question)) { next() }
                    .transition(.move(edge: .bottom))
            }
        }
        .confirmationDialog("现在退出？", isPresented: $isQuitting, titleVisibility: .visible) {
            Button("退出这一节", role: .destructive) { dismiss() }
            Button("接着刷", role: .cancel) {}
        } message: {
            Text("已经答过的题会记下来，但这一节不算完成。")
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { isQuitting = true } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("退出")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(Color.snack)
                        .frame(width: max(14, geo.size.width * run.progress))
                        .overlay(alignment: .top) {
                            Capsule().fill(.white.opacity(0.35)).frame(height: 4).padding(.horizontal, 6).padding(.top, 3)
                        }
                }
            }
            .frame(height: 16)
            .animation(.spring(duration: 0.4), value: run.progress)
            if run.combo >= 2 {
                Label("\(run.combo)", systemImage: "flame.fill")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.snack)
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(.snappy, value: run.combo >= 2)
    }

    @ViewBuilder
    private func game(_ q: Question) -> some View {
        let isLocked = result != nil
        switch q.game {
        case .choose:
            ChooseView(question: q, isLocked: isLocked) { take($0) }
        case .build:
            BuildView(question: q, isLocked: isLocked) { take($0) }
        case .type:
            TypeView(question: q, isLocked: isLocked) { take($0, typed: $1) }
        case .flip:
            FlipView(question: q) { take($0) }
        }
    }

    private func speaker(for q: Question) -> (() -> Void)? {
        guard let language = q.entry.deck.lang?.target else { return nil }
        return { Speaker.shared.say(q.card.back, language: language) }
    }

    private func take(_ attempt: Attempt, typed: String? = nil) {
        guard let r = run.answer(attempt) else { return }
        if let grade = r.grade {
            study.record(Review(card: r.question.key, grade: grade, at: .now, game: r.question.game, seconds: attempt.seconds))
        }
        if r.isCorrect { rights += 1 } else { wrongs += 1 }
        // A turned card has shown its answer already.
        if r.question.game == .flip {
            next()
            return
        }
        self.typed = typed
        withAnimation(.snappy(duration: 0.25)) { result = r }
        if speaks { speaker(for: r.question)?() }
    }

    private func next() {
        withAnimation(.snappy(duration: 0.3)) {
            result = nil
            typed = nil
            run.advance()
        }
        if run.isFinished { finish() }
    }

    private func finish() {
        let now = Date.now
        let wasDone = study.streak(at: now).isDoneToday
        study.finishLesson(run, started: started, deck: setup.deck, at: now)
        var learned = 0, leveledUp = 0
        for (key, old) in before {
            let new = study.mastery(key)
            if old == .new && new != .new { learned += 1 } else if new > old { leveledUp += 1 }
        }
        let streak = study.streak(at: now)
        withAnimation(.snappy) {
            end = LessonEnd(
                graded: run.graded.count, correct: run.correct, seconds: now.timeIntervalSince(started),
                bestCombo: run.bestCombo, learned: learned, leveledUp: leveledUp, streak: streak,
                isStreakNew: !wasDone && streak.isDoneToday, lessonsToday: study.lessons(on: Day(now)), goal: Prefs.goalValue
            )
        }
    }

    private func close() {
        dismiss()
        Task {
            await Reminders.requestPermission()
            await study.syncReminders()
        }
    }
}

/// What the answer was, sliding up once a question is answered.
private struct FeedbackPanel: View {
    let result: LessonRun.Result
    let typed: String?
    let onSpeak: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        let ok = result.isCorrect
        let color: Color = ok ? .right : .wrong
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Spacer()
                if let onSpeak {
                    Button(action: onSpeak) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(color)
                            .frame(width: 40, height: 40)
                    }
                }
            }
            if let typed, !ok || result.attempt.hasTypo {
                Text("你写的：\(typed)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                AnswerDetails(card: result.question.card)
            }
            .frame(maxHeight: 180)
            .fixedSize(horizontal: false, vertical: true)
            Button(ok ? "继续" : "知道了", action: onContinue)
                .buttonStyle(ChunkyButtonStyle(color: color))
        }
        .padding(20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(Color(.systemBackground))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24).fill(color.opacity(0.14)))
                .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var title: String {
        if !result.isCorrect { return result.attempt.gaveUp ? "答案是" : "正确答案" }
        if result.attempt.hasTypo { return "对了，注意拼写" }
        let cheers = ["答对了！", "漂亮！", "没错！", "很好！", "就是这样！"]
        return cheers[Int(UInt(bitPattern: result.question.id.hashValue) % UInt(cheers.count))]
    }
}
