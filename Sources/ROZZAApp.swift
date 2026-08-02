import SwiftUI

@main
struct ROZZAApp: App {
    @StateObject private var dj = DJPlaybackController()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topTrailing) {
                ROZZAWebAppView(dj: dj)
                    .ignoresSafeArea()
                DJLauncherButton(controller: dj)
            }
            .preferredColorScheme(.dark)
            .onAppear {
                try? ROZZAAudioSession.shared.configureAndActivateIfNeeded()
            }
        }
    }
}
