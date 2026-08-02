import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var source: ContentSource = .youtubeMusic
    @Published var filter: SearchFilter = .all
    @Published private(set) var results: [Track] = []
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private let providers: [SearchProvider]
    private var suggestionTask: Task<Void, Never>?

    init(providers: [SearchProvider]) {
        self.providers = providers
        recentSearches = UserDefaults.standard.stringArray(forKey: "rozza.recentSearches") ?? []
    }

    func queryChanged() {
        suggestionTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { suggestions = []; return }
        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            suggestions = (try? await activeProvider.suggestions(for: term)) ?? []
        }
    }

    func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        isLoading = true; errorMessage = nil; suggestions = []
        defer { isLoading = false }
        do {
            results = try await activeProvider.search(query: term, filter: filter, pageToken: nil).tracks
            recentSearches.removeAll { $0.localizedCaseInsensitiveCompare(term) == .orderedSame }
            recentSearches.insert(term, at: 0); recentSearches = Array(recentSearches.prefix(8))
            UserDefaults.standard.set(recentSearches, forKey: "rozza.recentSearches")
        } catch { results = []; errorMessage = error.localizedDescription }
    }
    func use(_ value: String) { query = value; Task { await search() } }
    func clearRecent() { recentSearches = []; UserDefaults.standard.removeObject(forKey: "rozza.recentSearches") }
    private var activeProvider: SearchProvider { providers.first { $0.source == source } ?? providers[0] }
}

