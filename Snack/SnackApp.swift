import SwiftUI

@main
struct SnackApp: App {
    @State private var inbox = Inbox()
    // `-SnackInMemory YES`: progress that is gone when the app is, for the UI test.
    @State private var study = Study(inMemory: UserDefaults.standard.bool(forKey: "SnackInMemory"))
    @Environment(\.scenePhase) private var phase

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(inbox: inbox, study: study)
                .task {
                    inbox.onRepeated = { [study] keys in study.recordRepeated(keys) }
                    await inbox.start()
                }
        }
        .onChange(of: phase) { _, phase in
            guard phase == .active else { return }
            inbox.refresh()
            Task { await study.syncReminders() }
        }
    }
}
