import SnackKit
import SwiftUI

/// The last page of a lesson: how it went, the streak, and the day's goal.
struct LessonEndView: View {
    let end: LessonEnd
    let onDone: () -> Void

    @State private var isShown = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill((end.isStreakNew ? Color.snack : Color.right).opacity(0.15))
                    .frame(width: 150, height: 150)
                    .scaleEffect(isShown ? 1 : 0.4)
                Image(systemName: end.isStreakNew ? "flame.fill" : end.accuracy == 1 ? "star.fill" : "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(end.isStreakNew ? Color.snack : end.accuracy == 1 ? Color.yellow : Color.right)
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

            HStack(spacing: 12) {
                stat("正确率", "\(Int((end.accuracy * 100).rounded()))%", end.accuracy >= 0.8 ? .right : .snack)
                stat("用时", duration, .blue)
                stat("最多连对", "\(end.bestCombo)", .snack)
            }

            if end.learned + end.leveledUp > 0 {
                Text(progressLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Ring(value: Double(end.lessonsToday) / Double(end.goal), color: end.lessonsToday >= end.goal ? .right : .snack, width: 8)
                    .frame(width: 44, height: 44)
                Text(goalLine).font(.headline)
            }
            Spacer()
            Button("完成", action: onDone)
                .buttonStyle(ChunkyButtonStyle())
        }
        .padding(24)
        .onAppear { isShown = true }
        .sensoryFeedback(.success, trigger: isShown)
    }

    private var title: String {
        end.graded > 0 && end.accuracy == 1 ? "全对！" : "这一节完成了"
    }

    private var duration: String {
        let s = Int(end.seconds.rounded())
        return s < 60 ? "\(s) 秒" : "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private var progressLine: String {
        [end.learned > 0 ? "新学 \(end.learned) 张" : nil, end.leveledUp > 0 ? "\(end.leveledUp) 张升级" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var goalLine: String {
        end.lessonsToday >= end.goal
            ? (end.lessonsToday == end.goal ? "今天的目标完成了 🎉" : "今天第 \(end.lessonsToday) 节，超额了")
            : "今天 \(end.lessonsToday)/\(end.goal) 节，还差 \(end.goal - end.lessonsToday) 节"
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.white)
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.systemBackground), in: .rect(cornerRadius: 10))
                .padding(.horizontal, 3)
                .padding(.bottom, 3)
        }
        .padding(.top, 6)
        .background(color, in: .rect(cornerRadius: 13))
    }
}
