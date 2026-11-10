import SwiftUI

struct RootView: View {
    let inbox: Inbox
    let study: Study
    /// Bumped to start a lesson, as the widget asks.
    let lessonAsked: Int

    @State private var tab = "today"

    var body: some View {
        TabView(selection: $tab) {
            Tab("今天", systemImage: "flame.fill", value: "today") {
                TodayView(inbox: inbox, study: study, lessonAsked: lessonAsked)
            }
            Tab("牌组", systemImage: "rectangle.stack.fill", value: "decks") {
                DecksView(inbox: inbox, study: study)
            }
        }
        .tint(Color.snack)
        .onChange(of: lessonAsked) { tab = "today" }
        .alert(inbox.notice ?? "", isPresented: Binding { inbox.notice != nil } set: { if !$0 { inbox.notice = nil } }) {
            Button("好") { inbox.notice = nil }
        }
    }
}
