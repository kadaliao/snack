import SwiftUI

struct RootView: View {
    let inbox: Inbox
    let study: Study

    var body: some View {
        TabView {
            Tab("今天", systemImage: "flame.fill") {
                TodayView(inbox: inbox, study: study)
            }
            Tab("牌组", systemImage: "rectangle.stack.fill") {
                DecksView(inbox: inbox, study: study)
            }
        }
        .tint(Color.snack)
    }
}
