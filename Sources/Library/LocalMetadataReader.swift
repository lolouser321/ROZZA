import AVFoundation
import Foundation

enum LocalMetadataReader {
    static func track(for url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        var title: String?, artist: String?, artworkURL: URL?
        for item in metadata {
            guard let key = item.commonKey else { continue }
            if key == .commonKeyTitle { title = try? await item.load(.stringValue) }
            if key == .commonKeyArtist { artist = try? await item.load(.stringValue) }
            if key == .commonKeyArtwork, let data = try? await item.load(.dataValue) {
                let destination = url.deletingLastPathComponent().appending(path: "\(url.deletingPathExtension().lastPathComponent)-artwork.jpg")
                if (try? data.write(to: destination, options: .atomic)) != nil { artworkURL = destination }
            }
        }
        let base = url.deletingPathExtension().lastPathComponent
        let pieces = base.components(separatedBy: " - ")
        return Track(id: "local-\(UUID().uuidString)", title: title ?? pieces.last ?? base, artist: artist ?? (pieces.count > 1 ? pieces[0] : "Imported Music"), artworkURL: artworkURL, duration: duration.isFinite ? duration : 0, source: .local, kind: .song, playbackURL: url, videoID: nil, capabilities: .local)
    }
}
