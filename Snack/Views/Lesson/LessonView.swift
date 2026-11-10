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
    var xp: Int
    var isPerfect: Bool
    /// Cards met for the first time.
    var learned: Int
    /// Cards known better than before.
    var leveledUp: Int
    var streak: Streak
    /// This lesson was the day's first, and the streak grew by it.
    var isStreakNew: Bool
    var freezeEarned: Bool
    var xpBefore: Int
    var xpToday: Int
    var goal: Int

    var accuracy: Double { graded == 0 ? 0 : Double(correct) / Double(graded) }
    /// This lesson reached the day's goal.
    var reachedGoal: Bool { xpBefore < goal && xpToday >= goal }
}

/// A lesson from first question to last page. Each first answer is graded and
/// logged at once, so leaving halfway keeps what was answered.
struct LessonView: View {
    let setup: LessonSetup
    let study: Study

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.speak) private var speaks = true

    @State private var run: LessonRun
    /// The results of the current question once answered, one per card.
    @State private var answered: [LessonRun.Result] = []
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
        var run = LessonRun(setup.questions)
        if Prefs.isQuiet { run.replaceCurrent { $0.withoutSound() } }
        _run = State(initialValue: run)
        _before = State(initialValue: Dictionary(
            setup.questions.flatMap(\.keys).map { ($0, study.mastery($0)) },
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
            if let first = answered.first {
                FeedbackPanel(results: answered, typed: typed, onSpeak: speaker(for: first.question)) { next() }
                    .transition(.move(edge: .bottom))
            }
        }
        .confirmationDialog("现在退出？", isPresented: $isQuitting, titleVisibility: .visible) {
            Button("退出这一节", role: .destructive) { dismiss() }
            Button("接着刷", role: .cancel) {}
        } message: {
            Text("已经答过的题会记下来，但这一节不算完成，也不加 XP。")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
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
            Label("\(run.answerXP)", systemImage: "bolt.fill")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.yellow.mix(with: .orange, by: 0.4))
                .contentTransition(.numericText())
                .accessibilityLabel("\(run.answerXP) XP")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(.snappy, value: run.combo >= 2)
        .animation(.snappy, value: run.answerXP)
    }

    @ViewBuilder
    private func game(_ q: Question) -> some View {
        let isLocked = !answered.isEmpty
        switch q.game {
        case .choose:
            ChooseView(question: q, isLocked: isLocked) { take($0) }
        case .match:
            MatchView(question: q) { take($0) }
        case .build:
            BuildView(question: q, isLocked: isLocked) { take($0) }
        case .listen:
            ListenView(question: q, isLocked: isLocked, onAnswer: { take($0) }, onQuiet: quiet)
        case .type, .cloze, .fix:
            TypeView(question: q, isLocked: isLocked) { take($0, typed: $1) }
        case .flip:
            FlipView(question: q) { take($0) }
        }
    }

    private func speaker(for q: Question) -> (() -> Void)? {
        guard q.game != .match, let language = q.language else { return nil }
        return { Speaker.shared.say(q.card.back, language: language) }
    }

    private func take(_ attempt: Attempt, typed: String? = nil) {
        let results = run.answer(attempt)
        guard let first = results.first else { return }
        let now = Date.now
        for r in results {
            if let grade = r.grade {
                study.record(Review(card: r.key, grade: grade, at: now, game: r.question.game, seconds: attempt.seconds))
            }
        }
        let isRight = attempt.isCorrect && !attempt.gaveUp
        if isRight { rights += 1 } else { wrongs += 1 }
        Sounds.shared.play(isRight ? .right : .wrong)
        // A turned card has shown its answer already.
        if first.question.game == .flip {
            next()
            return
        }
        self.typed = typed
        withAnimation(.snappy(duration: 0.25)) { answered = results }
        if speaks && !Prefs.isQuiet { speaker(for: first.question)?() }
    }

    /// No listening for a quarter of an hour: this question and the next heard
    /// ones are read instead, with nothing held against the card.
    private func quiet() {
        UserDefaults.standard.set(Date.now.addingTimeInterval(15 * 60), forKey: Prefs.quietUntil)
        withAnimation(.snappy) { run.replaceCurrent { $0.withoutSound() } }
    }

    private func next() {
        withAnimation(.snappy(duration: 0.3)) {
            answered = []
            typed = nil
            run.advance()
            if Prefs.isQuiet { run.replaceCurrent { $0.withoutSound() } }
        }
        if run.isFinished { finish() }
    }

    private func finish() {
        let now = Date.now
        let today = Day(now)
        let old = study.streak(at: now)
        let xpBefore = study.xp(on: today)
        study.finishLesson(run, started: started, deck: setup.deck, at: now)
        var learned = 0, leveledUp = 0
        for (key, was) in before {
            let new = study.mastery(key)
            if was == .new && new != .new { learned += 1 } else if new > was { leveledUp += 1 }
        }
        let streak = study.streak(at: now)
        Sounds.shared.play(.done)
        withAnimation(.snappy) {
            end = LessonEnd(
                graded: run.graded.count, correct: run.correct, seconds: now.timeIntervalSince(started),
                bestCombo: run.bestCombo, xp: run.xp, isPerfect: run.isPerfect, learned: learned, leveledUp: leveledUp,
                streak: streak, isStreakNew: !old.isDoneToday && streak.isDoneToday,
                freezeEarned: streak.freezes > old.freezes, xpBefore: xpBefore, xpToday: study.xp(on: today),
                goal: Prefs.goalValue
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
    let results: [LessonRun.Result]
    let typed: String?
    let onSpeak: (() -> Void)?
    let onContinue: () -> Void

    var body: some View {
        let first = results[0]
        let isMatch = first.question.game == .match
        let ok = isMatch ? results.allSatisfy(\.isCorrect) : first.isCorrect
        let color: Color = ok ? .right : .wrong
        let xp = results.reduce(0) { $0 + $1.xp }
        let bonus = results.reduce(0) { $0 + $1.bonus }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(title(first, ok: ok), systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(color)
                if xp > 0 {
                    Text(bonus > 0 ? "+\(xp) XP 连对加成" : "+\(xp) XP")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(bonus > 0 ? Color.snack : .yellow.mix(with: .orange, by: 0.4), in: .capsule)
                        .transition(.scale)
                }
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
            if isMatch {
                let missed = results.filter { !$0.isCorrect }
                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(missed, id: \.key) { r in
                            let card = first.question.group.first { $0.key == r.key }?.card
                            Text("\(card?.front ?? "") → \(card?.back ?? "")").font(.callout)
                        }
                        Text("这几张会在最后再问一次").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                if let typed, !ok || first.attempt.hasTypo {
                    Text("你写的：\(typed)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    AnswerDetails(card: first.question.card, showsFront: first.question.game == .listen)
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }
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

    private func title(_ r: LessonRun.Result, ok: Bool) -> String {
        if r.question.game == .match {
            let missed = results.count { !$0.isCorrect }
            return missed == 0 ? "全部配对！" : "配完了，错了 \(missed) 张"
        }
        if !ok { return r.attempt.gaveUp ? "答案是" : "正确答案" }
        if r.attempt.hasTypo { return "对了，注意拼写" }
        let cheers = ["答对了！", "漂亮！", "没错！", "很好！", "就是这样！"]
        return cheers[Int(UInt(bitPattern: r.question.id.hashValue) % UInt(cheers.count))]
    }
}
