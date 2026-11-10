import SnackKit
import SwiftUI

/// The first page: the streak, the day's goal, and the button that starts a lesson.
struct TodayView: View {
    let inbox: Inbox
    let study: Study

    @AppStorage(Prefs.goal) private var goal = 3
    @AppStorage(Prefs.newPerDay) private var newPerDay = 10
    @State private var lesson: LessonSetup?
    @State private var isSetting = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                page(now: context.date)
            }
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { isSetting = true }
                }
            }
            .sheet(isPresented: $isSetting) {
                SettingsView(study: study)
            }
            .fullScreenCover(item: $lesson) { setup in
                LessonView(setup: setup, study: study)
            }
        }
    }

    private func page(now: Date) -> some View {
        let entries = inbox.library.entries()
        let today = Day(now)
        let streak = study.streak(at: now)
        let done = study.lessons(on: today)
        let outlook = Planner().outlook(entries, progress: study.progress, now: now, newLeft: study.newLeft(at: now, perDay: newPerDay))
        return ScrollView {
            VStack(spacing: 16) {
                if let problem = study.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                StreakCard(streak: streak, today: today, days: Set(study.lessonsByDay.keys))
                GoalCard(done: done, goal: goal)
                start(entries: entries, outlook: outlook, now: now)
                if !entries.isEmpty {
                    MasteryBar(entries: entries, study: study)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func start(entries: [Entry], outlook: Planner.Outlook, now: Date) -> some View {
        VStack(spacing: 12) {
            if entries.isEmpty {
                ContentUnavailableView(
                    "还没有卡片",
                    systemImage: "tray",
                    description: Text("在「牌组」里看看怎么把卡片放进来。")
                )
            } else if outlook.due + outlook.new > 0 {
                Button { begin(entries) } label: {
                    VStack(spacing: 2) {
                        Text("开始一节")
                        Text(counts(outlook)).font(.caption.weight(.medium)).opacity(0.9)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(ChunkyButtonStyle())
            } else {
                Label("该复习的都复习完了", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.right)
                    .padding(.vertical, 4)
                if outlook.studied > 0 {
                    Button("再练一节") { begin(entries) }
                        .buttonStyle(ChunkyButtonStyle(color: .blue))
                }
                if outlook.unseen > 0 {
                    Button("多学 5 张新卡") { begin(entries, extraNew: 5) }
                        .buttonStyle(ChunkyButtonStyle(color: .right))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private func counts(_ o: Planner.Outlook) -> String {
        [o.due > 0 ? "\(o.due) 张待复习" : nil, o.new > 0 ? "\(o.new) 张新卡" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func begin(_ entries: [Entry], extraNew: Int = 0) {
        let questions = study.plan(entries, extraNew: extraNew)
        guard !questions.isEmpty else { return }
        lesson = LessonSetup(questions: questions)
    }
}

private struct StreakCard: View {
    let streak: Streak
    let today: Day
    let days: Set<Day>

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(streak.isDoneToday ? Color.snack : Color(.systemGray3))
                    .symbolEffect(.bounce, value: streak.isDoneToday)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(streak.count)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("天连胜").font(.headline)
                    }
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(streak.isAtRisk ? Color.snack : .secondary)
                }
                Spacer()
            }
            HStack {
                ForEach(-6...0, id: \.self) { offset in
                    let day = today.adding(offset)
                    VStack(spacing: 6) {
                        Text(weekday(day))
                            .font(.caption2.bold())
                            .foregroundStyle(offset == 0 ? .primary : .secondary)
                        ZStack {
                            Circle()
                                .fill(days.contains(day) ? Color.snack : Color(.systemGray5))
                            if days.contains(day) {
                                Image(systemName: "flame.fill").font(.caption).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(offset == 0 ? Color.snack : .clear, lineWidth: 2).padding(-3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }

    private var message: String {
        if streak.isDoneToday { return streak.count == 1 ? "第一天，明天再来" : "今天已经打卡" }
        if streak.isAtRisk { return "今天还没刷，刷一节续上连胜" }
        return streak.longest > 0 ? "最长连胜 \(streak.longest) 天，重新开始吧" : "刷完一节，连胜就开始了"
    }

    private func weekday(_ day: Day) -> String {
        ["日", "一", "二", "三", "四", "五", "六"][day.weekday - 1]
    }
}

private struct GoalCard: View {
    let done: Int
    let goal: Int

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Ring(value: Double(done) / Double(max(goal, 1)), color: done >= goal ? .right : .snack)
                Text("\(min(done, 99))/\(goal)")
                    .font(.headline.monospacedDigit())
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("今天的目标").font(.headline)
                Text(done >= goal ? "完成了，明天见 🎉" : "每天 \(goal) 节，一节两分钟左右")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

/// All cards by how well they are known, as one bar.
struct MasteryBar: View {
    let entries: [Entry]
    let study: Study

    var body: some View {
        let counts = Dictionary(grouping: entries, by: { study.mastery($0.key) }).mapValues(\.count)
        let total = max(entries.count, 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("\(entries.count) 张卡片").font(.headline)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Mastery.allCases.reversed(), id: \.self) { level in
                        if let n = counts[level], n > 0 {
                            Rectangle().fill(level.color)
                                .frame(width: max(3, (geo.size.width - 12) * Double(n) / Double(total)))
                        }
                    }
                }
                .clipShape(.capsule)
            }
            .frame(height: 12)
            FlowLayout(spacing: 12, lineSpacing: 6) {
                ForEach(Mastery.allCases.reversed(), id: \.self) { level in
                    if let n = counts[level], n > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(level.color).frame(width: 8, height: 8)
                            Text("\(level.label) \(n)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}
