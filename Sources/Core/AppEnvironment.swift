import Foundation

struct AppConfiguration: Sendable {
    let apiBaseURL: URL
    static func live(bundle: Bundle = .main) -> AppConfiguration {
        let raw = (bundle.object(forInfoDictionaryKey: "ROZZA_API_BASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw), url.scheme == "https" else {
            preconditionFailure("ROZZA_API_BASE_URL must be configured with an HTTPS URL")
        }
        return .init(apiBaseURL: url)
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
