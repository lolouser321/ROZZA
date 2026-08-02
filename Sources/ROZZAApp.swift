import SwiftUI

@main
struct ROZZAApp: App {
    var body: some Scene {
        WindowGroup {
            ROZZAWebAppView()
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
    }
}
