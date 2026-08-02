import SwiftUI
import MusicKit

struct MusicSourceSettings: View {
    @State private var appleStatus = MusicAuthorization.currentStatus
    @Environment(\.openURL) private var openURL
    var body: some View {
        Section("MUSIC SOURCES") {
            HStack { Image(systemName: "music.note").foregroundStyle(.red); VStack(alignment: .leading) { Text("Apple Music"); Text(appleStatus == .authorized ? "Authorized; catalog playback requires an active subscription." : "Connect your subscription for exact commercial recordings.").font(.caption).foregroundStyle(Theme.secondary) }; Spacer(); Button(appleStatus == .authorized ? "Connected" : "Connect") { Task { appleStatus = await MusicAuthorization.request() } }.disabled(appleStatus == .authorized) }
            HStack { Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green); VStack(alignment: .leading) { Text("Spotify"); Text("Playback opens in Spotify and uses Spotify's background controls.").font(.caption).foregroundStyle(Theme.secondary) }; Spacer(); Button("Open") { if let url = URL(string: "spotify:") { openURL(url) } } }
        }
    }
}
