import Foundation

struct AIChatResult: Sendable { let message: String; let tracks: [Track] }

struct AIService: Sendable {
    let api: APIClient
    func chat(message: String, sessionID: String, currentTrack: Track?) async throws -> AIChatResult {
        struct Request: Encodable { let message, sessionId: String; let currentTrack: Context?; struct Context: Encodable { let title, artist, genre, language: String } }
        struct Response: Decodable { let explanation: String?; let tracks: [DTO]? }
        struct DTO: Decodable { let id, title, artist: String; let artwork: String?; let durationSeconds: Double?; let sources: [Source] }
        struct Source: Decodable { let provider, providerId: String; let url: String?; let canPlay, canBackgroundPlay, canDownload, canOfflinePlay, supportsLockScreen, supportsControlCenter: Bool? }
        let context = currentTrack.map { Request.Context(title: $0.title, artist: $0.artist, genre: "", language: "") }
        let data = try JSONEncoder().encode(Request(message: message, sessionId: sessionID, currentTrack: context))
        let response = try JSONDecoder().decode(Response.self, from: await api.postData("api/ai/chat", json: data))
        let tracks = (response.tracks ?? []).compactMap { dto -> Track? in
            guard let source = dto.sources.first(where: { $0.canPlay ?? true }) else { return nil }
            let youtube = source.provider == "youtube"
            return Track(id: dto.id, title: dto.title, artist: dto.artist, artworkURL: dto.artwork.flatMap(URL.init(string:)), duration: dto.durationSeconds ?? 0, source: youtube ? .youtube : .licensed, kind: youtube ? .video : .song, playbackURL: source.url.flatMap(URL.init(string:)), videoID: youtube ? source.providerId : nil, capabilities: youtube ? .youtube : .init(canPlay: source.canPlay ?? true, canBackgroundPlay: source.canBackgroundPlay ?? true, canDownload: source.canDownload ?? false, canOfflinePlay: source.canOfflinePlay ?? false, supportsLockScreen: source.supportsLockScreen ?? true, supportsControlCenter: source.supportsControlCenter ?? true))
        }
        return .init(message: response.explanation ?? "Here is what I found.", tracks: tracks)
    }
}

