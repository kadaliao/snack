#if DEBUG
import SwiftUI
import WidgetKit

/// `-SnackWidgetGallery YES`: the widget's faces at their sizes, from the
/// snapshot the app wrote, for the UI test to look at.
struct WidgetGallery: View {
    var body: some View {
        let state = WidgetSnapshot.load()?.state(at: .now)
            ?? .init(streak: 7, isDoneToday: false, isAtRisk: true, xp: 120, goal: 300, due: 12, new: 10)
        let entry = WidgetEntry(date: .now, state: state)
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    face(entry, .systemSmall, width: 170, height: 170)
                    VStack(spacing: 12) {
                        face(entry, .accessoryCircular, width: 72, height: 72, dark: true)
                        face(entry, .accessoryInline, width: 170, height: 24, dark: true)
                    }
                }
                face(entry, .systemMedium, width: 364, height: 170)
                face(entry, .accessoryRectangular, width: 172, height: 76, dark: true)
                let tomorrow = WidgetEntry(date: .now, state: WidgetSnapshot.load()?.state(at: Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400 + 60)))
                Text("明天零点").font(.caption)
                face(tomorrow, .systemSmall, width: 170, height: 170)
            }
            .padding()
        }
        .background(Color(.systemGray5))
    }

    private func face(_ entry: WidgetEntry, _ family: WidgetFamily, width: CGFloat, height: CGFloat, dark: Bool = false) -> some View {
        let isAccessory = [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
        return WidgetView(entry: entry, size: family)
            .padding(isAccessory ? 4 : 16)
            .frame(width: width, height: height)
            .background(dark ? Color.black : Color(.systemBackground), in: .rect(cornerRadius: isAccessory ? 12 : 22))
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}
#endif
