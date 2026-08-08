import Foundation
import SwiftData

@Model final class SavedTrack {
    @Attribute(.unique) var trackID: String
    var payload: Data
    var isFavorite: Bool
    var isDownloaded: Bool
    var lastPlayedAt: Date?
    init(track: Track, favorite: Bool = false, downloaded: Bool = false) {
        trackID = track.id; payload = (try? JSONEncoder().encode(track)) ?? Data(); isFavorite = favorite; isDownloaded = downloaded
    }
    var track: Track? { try? JSONDecoder().decode(Track.self, from: payload) }
}

@Model final class SavedPlaylist {
    @Attribute(.unique) var id: UUID
    var name: String
    var trackIDs: [String]
    var createdAt: Date
    init(name: String) { id = UUID(); self.name = name; trackIDs = []; createdAt = .now }
}

