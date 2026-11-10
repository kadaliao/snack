import SwiftUI
import WidgetKit

@main
struct SnackWidgets: WidgetBundle {
    var body: some Widget {
        SnackWidget()
    }
}

/// The streak, the day's points, and the cards due, at a glance; a tap starts a lesson.
struct SnackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Snack", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
                .widgetURL(WidgetSnapshot.lessonURL)
        }
        .configurationDisplayName("卡片零食")
        .description("连胜、今天的 XP 和待复习的卡，点一下就开始一节。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, state: .init(streak: 7, isDoneToday: false, isAtRisk: true, xp: 120, goal: 300, due: 12, new: 10))
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(context.isPreview && WidgetSnapshot.load() == nil ? placeholder(in: context) : entry(at: .now))
    }

    /// An entry now, at each time cards come due, and at the next two midnights.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        var times: Set<Date> = [now]
        if let snapshot = WidgetSnapshot.load() {
            for date in snapshot.upcoming where date > now {
                // To the quarter hour: one entry for cards due close together.
                let quarter = (date.timeIntervalSinceReferenceDate / 900).rounded(.up) * 900
                times.insert(Date(timeIntervalSinceReferenceDate: quarter))
            }
        }
        let midnight = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        times.insert(midnight)
        times.insert(midnight.addingTimeInterval(86_400))
        let entries = times.sorted().prefix(60).map { entry(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> WidgetEntry {
        WidgetEntry(date: date, state: WidgetSnapshot.load()?.state(at: date))
    }
}

