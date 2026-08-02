import Foundation

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    init(baseURL: URL, session: URLSession = .shared) { self.baseURL = baseURL; self.session = session }

    func post<Request: Encodable, Response: Decodable>(_ path: String, body: Request) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw ROZZAError.network("ROZZA could not reach the music service.")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func upload(_ path: String, data: Data, filename: String, mimeType: String) async throws -> Data {
        let boundary = "ROZZA-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: path)); request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data(); body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!); body.append(data); body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let (responseData, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ROZZAError.network("Recognition service is unavailable.") }
        return responseData
    }

    func postData(_ path: String, json: Data) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = json
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ROZZAError.network("ROZZA's service is temporarily unavailable.") }
        return data
    }

    func uploadAudio(_ fileURL: URL) async throws -> Data {
        let boundary = "ROZZA-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "api/recognition/identify"))
        request.httpMethod = "POST"; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data(); body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"sample.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL)); body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw ROZZAError.network("Music recognition is unavailable.") }
        return data
    }
}

private struct SearchRequest: Encodable { let query: String }
struct BackendResponse: Decodable { let tracks: [BackendTrack]; let totalResults: Int? }
struct BackendTrack: Decodable {
    let id, title, artist: String
    let artwork: String?
    let durationSeconds: Double?
    let sources: [BackendSource]
}
struct BackendSource: Decodable {
    let provider, providerId: String
    let url: String?
    let canPlay, canBackgroundPlay, canDownload, canOfflinePlay, supportsLockScreen, supportsControlCenter: Bool?
}

struct AIChatRequest: Encodable { let message: String; let sessionId: String? }
struct AIChatResponse: Decodable {
    let sessionId: String
    let tracks: [BackendTrack]
    let explanation: String?
    let provider: String?
    let model: String?
}
struct RecognitionResponse: Decodable { let found: Bool; let track: RecognitionTrack?; let message: String? }
struct RecognitionTrack: Decodable { let title, artist, album, artwork, youtubeVideoId, previewUrl: String? }

extension BackendTrack {
    func asTrack(preferredSource: ContentSource = .youtubeMusic) -> Track? {
        guard let selected = sources.first(where: { $0.canPlay ?? true }) else { return nil }
        let isYouTube = selected.provider == "youtube"
        return Track(id: id, title: title, artist: artist, artworkURL: artwork.flatMap(URL.init(string:)), duration: durationSeconds ?? 0, source: isYouTube ? preferredSource : .licensed, kind: isYouTube ? .video : .song, playbackURL: selected.url.flatMap(URL.init(string:)), videoID: isYouTube ? selected.providerId : nil, capabilities: isYouTube ? .youtube : .nativeStream)
    }
}

struct BackendSearchProvider: SearchProvider {
    let api: APIClient
    let source: ContentSource

    func search(query: String, filter: SearchFilter, pageToken: String?) async throws -> SearchPage {
        let response: BackendResponse = try await api.post("api/search/full", body: SearchRequest(query: query))
        let mapped = response.tracks.compactMap { item -> Track? in
            let preferred = item.sources.first { backend in
                source == .youtube ? backend.provider == "youtube" : backend.provider == "youtube" || backend.provider == "audius" || backend.provider == "jamendo"
            }
            guard let preferred else { return nil }
            let isYouTube = preferred.provider == "youtube"
            let kind: ContentKind = isYouTube ? .video : .song
            guard filter == .all || (filter == .songs && kind == .song) || (filter == .videos && kind == .video) else { return nil }
            return Track(
                id: item.id, title: item.title, artist: item.artist,
                artworkURL: item.artwork.flatMap(URL.init(string:)), duration: item.durationSeconds ?? 0,
                source: isYouTube ? source : .licensed, kind: kind,
                playbackURL: preferred.url.flatMap(URL.init(string:)), videoID: isYouTube ? preferred.providerId : nil,
                capabilities: isYouTube ? .youtube : .init(
                    canPlay: preferred.canPlay ?? true,
                    canBackgroundPlay: preferred.canBackgroundPlay ?? true,
                    canDownload: preferred.canDownload ?? false,
                    canOfflinePlay: preferred.canOfflinePlay ?? false,
                    supportsLockScreen: preferred.supportsLockScreen ?? true,
                    supportsControlCenter: preferred.supportsControlCenter ?? true)
            )
        }
        return SearchPage(tracks: mapped, nextPageToken: nil)
    }

    func suggestions(for query: String) async throws -> [String] {
        struct SuggestionRequest: Encodable { let query: String }
        struct SuggestionResponse: Decodable { let suggestions: [String] }
        let response: SuggestionResponse = try await api.post("api/search/autocomplete", body: SuggestionRequest(query: query))
        return response.suggestions
    }
}
