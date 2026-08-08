import SwiftUI

struct CachedArtwork: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url, transaction: .init(animation: .easeInOut)) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .failure: fallback
            default: ZStack { Theme.elevated; ProgressView().tint(Theme.orange) }
            }
        }.clipped()
    }
    private var fallback: some View { ZStack { Theme.elevated; Image(systemName: "music.note").foregroundStyle(Theme.orange) } }
}

struct TrackRow: View {
    let track: Track
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CachedArtwork(url: track.artworkURL).frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(track.title).font(.body.weight(.semibold)).foregroundStyle(.white).lineLimit(2).multilineTextAlignment(.leading)
                    Text(track.artist).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(track.kind.rawValue.capitalized)
                        Text(track.capabilities.canBackgroundPlay ? "Background" : "Foreground only")
                    }.font(.caption2.weight(.medium)).foregroundStyle(track.capabilities.canBackgroundPlay ? Theme.orange : Theme.secondary)
                }
                Spacer(); Image(systemName: "play.fill").foregroundStyle(Theme.orange)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Play \(track.title) by \(track.artist)")
    }
}

struct LoadingSkeleton: View {
    var body: some View { VStack(spacing: 14) { ForEach(0..<6, id: \.self) { _ in HStack { RoundedRectangle(cornerRadius: 8).fill(Theme.elevated).frame(width: 58, height: 58); VStack { RoundedRectangle(cornerRadius: 4).fill(Theme.elevated).frame(height: 14); RoundedRectangle(cornerRadius: 4).fill(Theme.elevated).frame(width: 130, height: 10) }; Spacer() }.redacted(reason: .placeholder) } }.accessibilityLabel("Loading") }
}

