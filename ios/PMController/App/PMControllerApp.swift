import SwiftUI

@main
struct PMControllerApp: App {
    // @StateObject rather than @State: Session is an ObservableObject so
    // the app runs on iOS 16, where @Observable does not exist.
    @StateObject private var session: Session = AppConfig.isPreview
        ? .preview(persona: AppConfig.previewPersona)
        : Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task { await session.start() }
        }
    }
}
