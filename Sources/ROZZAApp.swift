import SwiftUI
import SwiftData

@main
struct ROZZAApp: App {
    @StateObject private var environment = AppEnvironment()
    private let container: ModelContainer = {
        do { return try ModelContainer(for: SavedTrack.self, SavedPlaylist.self) }
        catch { fatalError("Unable to create ROZZA library: \(error)") }
    }()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(environment).environment(\.layoutDirection, currentDirection) }
            .modelContainer(container)
    }
    private var currentDirection: LayoutDirection { Locale.Language(identifier: Locale.current.language.languageCode?.identifier ?? "en").characterDirection == .rightToLeft ? .rightToLeft : .leftToRight }
}
