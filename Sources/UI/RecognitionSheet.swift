import SwiftUI

struct RecognitionSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RecognitionViewModel()
    var body: some View {
        NavigationStack { VStack(spacing: 24) { Spacer(); content; Spacer(); if model.state != .idle { Button("Cancel") { model.cancel(); dismiss() }.foregroundStyle(Theme.secondary) } }.padding(24).navigationTitle("ROZZA Listen").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { model.cancel(); dismiss() } } }.premiumBackground() }
    }
    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle: Text("Tap to identify music playing around you").foregroundStyle(Theme.secondary); Button { Task { await model.start(api: env.api) } } label: { Image(systemName: "mic.fill").font(.system(size: 48)).frame(width: 160, height: 160).background(RadialGradient(colors: [Theme.accent, Theme.accent.opacity(0.3)], center: .center, startRadius: 5, endRadius: 80)).clipShape(Circle()).shadow(color: Theme.accent.opacity(0.5), radius: 24) }
        case .permission: ProgressView(); Text("Requesting microphone access…")
        case .listening: ProgressView().scaleEffect(1.6).tint(Theme.cyan); Text("Listening for 8 seconds…").font(.title3.bold())
        case .processing: ProgressView().scaleEffect(1.5); Text("Analyzing audio with AudD…").foregroundStyle(Theme.secondary)
        case .notFound: ContentUnavailableView("No matching track", systemImage: "waveform.badge.magnifyingglass", description: Text("Make sure the music is clearly audible.")); retry
        case .failed: ContentUnavailableView("Listen unavailable", systemImage: "exclamationmark.triangle", description: Text(model.errorMessage)); retry
        case .found: if let track = model.result { Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.cyan); CachedArtwork(url: track.artworkURL).frame(width: 190, height: 190).clipShape(RoundedRectangle(cornerRadius: 22)); Text(track.title).font(.title2.bold()).multilineTextAlignment(.center); Text(track.artist).foregroundStyle(Theme.secondary); Button { Task { await env.playback.play(track); dismiss(); env.playback.isFullPlayerPresented = true } } label: { Label("Play Now", systemImage: "play.fill").frame(maxWidth: .infinity).padding() }.buttonStyle(.borderedProminent) }
        }
    }
    private var retry: some View { Button("Try Again") { Task { await model.start(api: env.api) } }.buttonStyle(.borderedProminent) }
}
