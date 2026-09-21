import SwiftUI

@main
struct PMControllerApp: App {
    @State private var session: Session = AppConfig.isPreview
        ? .preview(persona: AppConfig.previewPersona)
        : Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.start() }
        }
    }
}
