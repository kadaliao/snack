import SwiftUI

@main
struct SnackApp: App {
    @State private var inbox = Inbox()
    // `-SnackInMemory YES`: progress that is gone when the app is, for the UI test.
    @State private var study = Study(inMemory: UserDefaults.standard.bool(forKey: "SnackInMemory"))
    @Environment(\.scenePhase) private var phase
    /// Bumped to start a lesson, as the widget asks.
    @State private var lessonAsked = 0

    init() {
        Prefs.register()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "SnackWidgetGallery") {
                WidgetGallery()
            } else {
                root
            }
            #else
            root
            #endif
        }
        .onChange(of: phase) { _, phase in
            switch phase {
            case .active:
                inbox.refresh()
                WidgetBridge.update(library: inbox.library, study: study)
                Task { await study.syncReminders() }
            case .background:
                WidgetBridge.update(library: inbox.library, study: study)
            default:
                break
            }
        }
    }

    private var root: some View {
        RootView(inbox: inbox, study: study, lessonAsked: lessonAsked)
            .onOpenURL { url in
                if url == WidgetSnapshot.lessonURL { lessonAsked += 1 }
            }
            .task {
                inbox.onRepeated = { [study] keys in study.recordRepeated(keys) }
                await inbox.start()
            }
    }
}
