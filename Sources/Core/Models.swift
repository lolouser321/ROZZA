import Foundation

enum ContentSource: String, Codable, Sendable { case youtubeMusic, youtube, local, licensed }
enum ContentKind: String, Codable, CaseIterable, Sendable { case song, video, artist, playlist }
enum RepeatMode: String, Codable, Sendable { case off, one, all }

struct PlaybackCapabilities: Codable, Hashable, Sendable {
    let canPlay: Bool
    let canBackgroundPlay: Bool
    let canDownload: Bool
    let canOfflinePlay: Bool
    let supportsLockScreen: Bool
    let supportsControlCenter: Bool

    static let youtube = Self(canPlay: true, canBackgroundPlay: false, canDownload: false, canOfflinePlay: false, supportsLockScreen: false, supportsControlCenter: false)
    static let nativeStream = Self(canPlay: true, canBackgroundPlay: true, canDownload: false, canOfflinePlay: false, supportsLockScreen: true, supportsControlCenter: true)
    static let local = Self(canPlay: true, canBackgroundPlay: true, canDownload: true, canOfflinePlay: true, supportsLockScreen: true, supportsControlCenter: true)
}

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    var artist: String
    var artworkURL: URL?
    var duration: TimeInterval
    var source: ContentSource
    var kind: ContentKind
    var playbackURL: URL?
    var videoID: String?
    var capabilities: PlaybackCapabilities
}

struct SearchPage: Sendable {
    var tracks: [Track]
    var nextPageToken: String?
}

enum SearchFilter: String, CaseIterable, Identifiable {
    case all, songs, videos, artists, playlists
    var id: String { rawValue }
    var title: LocalizedStringKeyValue {
        switch self { case .all: "All"; case .songs: "Songs"; case .videos: "Videos"; case .artists: "Artists"; case .playlists: "Playlists" }
    }
}
typealias LocalizedStringKeyValue = String

