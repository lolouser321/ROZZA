import SwiftUI

@main
struct ROZZAApp: App {
    @StateObject private var dj = DJPlaybackController()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topTrailing) {
                ROZZAWebAppView(dj: dj)
                    .ignoresSafeArea()
#if DEBUG
                DJLauncherButton(controller: dj)
#endif
            }
            .preferredColorScheme(.dark)
        }
    }
}
