import SwiftUI

@main
struct SnackApp: App {
    @State private var inbox = Inbox()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            DecksView(inbox: inbox)
                .task { await inbox.start() }
        }
        .onChange(of: phase) { _, phase in
            if phase == .active { inbox.refresh() }
        }
    }
}
