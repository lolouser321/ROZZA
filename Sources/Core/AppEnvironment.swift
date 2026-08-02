import Foundation

struct AppConfiguration: Sendable {
    let apiBaseURL: URL
    static func live(bundle: Bundle = .main) -> AppConfiguration {
        let raw = (bundle.object(forInfoDictionaryKey: "ROZZA_API_BASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Local-only fallback. Release CI injects ROZZA_API_BASE_URL from a
        // GitHub repository variable; provider credentials remain server-side.
        let fallback = URL(string: "http://127.0.0.1:3001")!
        return .init(apiBaseURL: URL(string: raw).flatMap { $0.scheme == nil ? nil : $0 } ?? fallback)
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let configuration: AppConfiguration
    let api: APIClient
    let playback: PlaybackManager
    let search: SearchViewModel

    init(configuration: AppConfiguration = .live()) {
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        self.configuration = configuration
        let api = APIClient(baseURL: configuration.apiBaseURL)
        self.api = api
        self.playback = PlaybackManager()
        self.search = SearchViewModel(providers: [BackendSearchProvider(api: api, source: .youtubeMusic), BackendSearchProvider(api: api, source: .youtube)])
    }
}
