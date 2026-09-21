//
//  PM Controller
//  Copyright © 2026 Apex Plumbing and Mechanical Services SC. All rights reserved.
//
//  Proprietary and confidential. See LICENSE at the repository root.
//

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
