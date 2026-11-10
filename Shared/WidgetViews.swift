import SwiftUI
import WidgetKit

/// The widget's faces. Also built into the app, where a debug gallery shows them.
struct WidgetView: View {
    let entry: WidgetEntry
    /// Given by the debug gallery; otherwise the widget's own.
    var size: WidgetFamily?
    @Environment(\.widgetFamily) private var widgetFamily

    private var family: WidgetFamily { size ?? widgetFamily }

    private let orange = Color.orange

    var body: some View {
        if let s = entry.state {
            switch family {
            case .accessoryCircular: circular(s)
            case .accessoryRectangular: rectangular(s)
            case .accessoryInline: Text("🔥\(s.streak) · \(s.due) 张待复习")
            case .systemMedium: medium(s)
            default: small(s)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.title).foregroundStyle(orange)
                Text("打开卡片零食，刷第一节").font(.caption).multilineTextAlignment(.center)
            }
        }
    }

    private func flame(_ s: WidgetSnapshot.State) -> Color {
        s.isDoneToday ? orange : Color(.systemGray3)
    }

    private func line(_ s: WidgetSnapshot.State) -> String {
        if s.due > 0 { return "\(s.due) 张待复习" }
        if s.new > 0 { return "\(s.new) 张新卡" }
        return "都复习完了"
    }

    private func small(_ s: WidgetSnapshot.State) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(flame(s)).font(.title2)
                Text("\(s.streak)").font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("天").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text(s.isAtRisk ? "今天还没刷" : s.isDoneToday ? "今天已打卡" : "开始连胜")
                .font(.caption.bold())
                .foregroundStyle(s.isAtRisk ? orange : .secondary)
            Spacer(minLength: 0)
            ProgressView(value: Double(min(s.xp, s.goal)), total: Double(max(s.goal, 1)))
                .tint(s.xp >= s.goal ? .green : orange)
            HStack {
                Text("\(s.xp)/\(s.goal) XP")
                Spacer()
                Text(line(s))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func medium(_ s: WidgetSnapshot.State) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(flame(s)).font(.largeTitle)
                Text("\(s.streak) 天连胜").font(.headline)
                Text(s.isAtRisk ? "今天还没刷" : s.isDoneToday ? "今天已打卡" : "刷一节开始连胜")
                    .font(.caption)
                    .foregroundStyle(s.isAtRisk ? orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, Double(s.xp) / Double(max(s.goal, 1))))
                    .stroke(s.xp >= s.goal ? Color.green : orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(s.xp)").font(.headline.monospacedDigit())
                    Text("/\(s.goal) XP").font(.system(size: 9).bold()).foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 8) {
                Text(line(s)).font(.subheadline.bold())
                Text("开始一节")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(orange, in: .capsule)
            }
        }
    }

    private func circular(_ s: WidgetSnapshot.State) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.caption)
                Text("\(s.streak)").font(.title3.bold().monospacedDigit())
            }
        }
        .widgetAccentable()
    }

    private func rectangular(_ s: WidgetSnapshot.State) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("\(s.streak) 天连胜", systemImage: "flame.fill").font(.headline).widgetAccentable()
            Text(line(s)).font(.caption)
            Text(s.isAtRisk ? "今天还没刷" : "\(s.xp)/\(s.goal) XP").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetEntry: TimelineEntry {
    var date: Date
    var state: WidgetSnapshot.State?
}
