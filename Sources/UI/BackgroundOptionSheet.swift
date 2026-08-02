import SwiftUI

struct BackgroundOptionSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var alternative: Track?
    @State private var loading = true
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("This track stops when your screen locks", systemImage: "lock.slash").font(.title2.bold()).foregroundStyle(Theme.accent)
                Text("“\(track.title)” is using YouTube’s visible player. ROZZA cannot turn that protected video into hidden background audio.").foregroundStyle(Theme.secondary)
                if loading { ProgressView("Looking for a permitted background version…").tint(Theme.accent) }
                else if let alternative { TrackRow(track: alternative) { Task { await env.playback.play(alternative); env.playback.foregroundOnlyNotice = nil; dismiss() } }; Text("This may be a different licensed recording, remix, or cover.").font(.caption).foregroundStyle(.orange) }
                else { Label("No background-capable version was found. You can import an MP3/M4A you legally own from Library.", systemImage: "folder.badge.plus").foregroundStyle(Theme.secondary) }
                Spacer()
                Button { env.playback.foregroundOnlyNotice = nil; dismiss() } label: { Text("Continue with YouTube (foreground only)").frame(maxWidth: .infinity).padding() }.buttonStyle(.bordered)
            }.padding(22).navigationTitle("Playback Source").navigationBarTitleDisplayMode(.inline).task { await findAlternative() }.premiumBackground()
        }
    }
    private func findAlternative() async {
        defer { loading = false }
        let query = "\(track.title) \(track.artist)"
        guard let page = try? await BackendSearchProvider(api: env.api, source: .youtubeMusic).search(query: query, filter: .songs, pageToken: nil) else { return }
        alternative = page.tracks.first { $0.capabilities.canBackgroundPlay }
    }
}

