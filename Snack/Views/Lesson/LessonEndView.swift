import SnackKit
import SwiftUI

/// The last page of a lesson: the points, how it went, the streak, and the day's goal.
struct LessonEndView: View {
    let end: LessonEnd
    let onDone: () -> Void

    @State private var isShown = false
    @State private var shownXP = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 150, height: 150)
                    .scaleEffect(isShown ? 1 : 0.4)
                Image(systemName: symbol)
                    .font(.system(size: 72))
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, value: isShown)
                    .scaleEffect(isShown ? 1 : 0.2)
            }
            .animation(.spring(duration: 0.6, bounce: 0.5), value: isShown)

            VStack(spacing: 8) {
                Text(title).font(.largeTitle.bold())
                if end.isStreakNew {
                    Text("连胜 \(end.streak.count) 天")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.snack)
                }
            }

            HStack(spacing: 10) {
                stat("XP", "\(shownXP)", .yellow.mix(with: .orange, by: 0.4))
                stat("正确率", "\(Int((end.accuracy * 100).rounded()))%", end.accuracy >= 0.8 ? .right : .snack)
                stat("用时", duration, .blue)
                stat("连对", "\(end.bestCombo)", .snack)
            }

            VStack(spacing: 6) {
                if end.learned + end.leveledUp > 0 {
                    Text(progressLine)
                }
                if end.freezeEarned {
                    Label("得到一张冻结卡：哪天没刷，连胜也不会断", systemImage: "snowflake")
                        .foregroundStyle(.cyan)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Ring(value: Double(end.xpToday) / Double(end.goal), color: end.xpToday >= end.goal ? .right : .snack, width: 8)
                    .frame(width: 44, height: 44)
                Text(goalLine).font(.headline)
            }
            Spacer()
            Button("完成", action: onDone)
                .buttonStyle(ChunkyButtonStyle())
        }
        .padding(24)
        .overlay {
            if end.reachedGoal || end.isPerfect {
                Confetti()
            }
        }
        .onAppear {
            isShown = true
            countUp()
        }
        .sensoryFeedback(.success, trigger: isShown)
    }

    private var accent: Color {
        end.isStreakNew ? .snack : end.isPerfect ? .yellow : .right
    }

    private var symbol: String {
        end.isStreakNew ? "flame.fill" : end.isPerfect ? "star.fill" : "checkmark.seal.fill"
    }

    private var title: String {
        end.isPerfect ? "全对！" : "这一节完成了"
    }

    private var duration: String {
        let s = Int(end.seconds.rounded())
        return s < 60 ? "\(s)秒" : "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private var progressLine: String {
        [end.learned > 0 ? "新学 \(end.learned) 张" : nil, end.leveledUp > 0 ? "\(end.leveledUp) 张升级" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var goalLine: String {
        if end.reachedGoal { return "今天的目标完成了 🎉" }
        if end.xpToday >= end.goal { return "今天 \(end.xpToday) XP，超过目标了" }
        return "今天 \(end.xpToday)/\(end.goal) XP"
    }

    /// The points counted up from nothing.
    private func countUp() {
        let steps = 20
        Task {
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(35))
                withAnimation(.snappy(duration: 0.1)) { shownXP = end.xp * i / steps }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.white)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.systemBackground), in: .rect(cornerRadius: 10))
                .padding(.horizontal, 3)
                .padding(.bottom, 3)
        }
        .padding(.top, 6)
        .background(color, in: .rect(cornerRadius: 13))
    }
}

/// Paper bits flung up from the middle, falling away over three seconds.
struct Confetti: View {
    @State private var start = Date.now
    private static let colors: [Color] = [.orange, .yellow, .green, .blue, .pink, .purple, .red]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard t < 3.2 else { return }
                ctx.opacity = min(1, max(0, (3.2 - t) / 0.8))
                for i in 0..<90 {
                    var rng = SplitMix64(seed: UInt64(i) &* 0x9E37_79B9 &+ 7)
                    let angle = Double.random(in: (-0.92 * .pi)...(-0.08 * .pi), using: &rng)
                    let speed = Double.random(in: 420...900, using: &rng)
                    let x = size.width / 2 + cos(angle) * speed * t
                    let y = size.height * 0.3 + sin(angle) * speed * t + 700 * t * t
                    let w = Double.random(in: 7...12, using: &rng)
                    let spin = Double.random(in: -9...9, using: &rng) * t
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(spin))
                    piece.fill(
                        Path(roundedRect: CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2), cornerRadius: 1.5),
                        with: .color(Self.colors[i % Self.colors.count])
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
