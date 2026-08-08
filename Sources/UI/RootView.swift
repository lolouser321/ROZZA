import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.modelContext) private var modelContext
    @Namespace private var playerNamespace
    @State private var selectedTab = 0
    @State private var showAI = false
    @State private var showListen = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onExplore: { selectedTab = 1 }, onAI: { showAI = true }, onListen: { showListen = true }).tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            ExploreView(onAI: { showAI = true }, onListen: { showListen = true }).tabItem { Label("Explore", systemImage: "magnifyingglass") }.tag(1)
            LibraryView().tabItem { Label("Library", systemImage: "square.stack.fill") }.tag(2)
            TrendingView().tabItem { Label("Trending", systemImage: "chart.line.uptrend.xyaxis") }.tag(3)
            AccountView().tabItem { Label("Account", systemImage: "person.crop.circle") }.tag(4)
        }
        .toolbarBackground(Theme.background.opacity(0.98), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if environment.playback.currentTrack != nil {
                MiniPlayer(namespace: playerNamespace)
                    .padding(.vertical, 5)
                    .background(Theme.background.opacity(0.98))
            }
        }
        .premiumBackground()
        .fullScreenCover(isPresented: Binding(get: { environment.playback.isFullPlayerPresented }, set: { environment.playback.isFullPlayerPresented = $0 })) { NowPlayingView(namespace: playerNamespace) }
        .sheet(isPresented: $showAI) { AISheet() }
        .sheet(isPresented: $showListen) { ListenRecognitionView(api: environment.api) }
        .sheet(item: Binding(get: { environment.playback.foregroundOnlyNotice }, set: { environment.playback.foregroundOnlyNotice = $0 })) { track in BackgroundOptionSheet(track: track) }
        .onReceive(environment.playback.$currentTrack.compactMap { $0 }) { track in recordHistory(track) }
    }

    private func recordHistory(_ track: Track) {
        let id = track.id
        let descriptor = FetchDescriptor<SavedTrack>(predicate: #Predicate { $0.trackID == id })
        if let saved = try? modelContext.fetch(descriptor).first { saved.lastPlayedAt = .now; saved.payload = (try? JSONEncoder().encode(track)) ?? saved.payload }
        else { let saved = SavedTrack(track: track); saved.lastPlayedAt = .now; modelContext.insert(saved) }
        try? modelContext.save()
    }
}

struct MiniPlayer: View {
    @EnvironmentObject private var env: AppEnvironment
    let namespace: Namespace.ID
    var body: some View {
        if let track = env.playback.currentTrack {
            Button { env.playback.isFullPlayerPresented = true } label: {
                HStack(spacing: 10) {
                    CachedArtwork(url: track.artworkURL).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 7)).matchedGeometryEffect(id: "artwork", in: namespace)
                    VStack(alignment: .leading, spacing: 2) { Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1); Text(track.artist).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1) }
                    Spacer()
                    Button { Task { await env.playback.toggle() } } label: { Image(systemName: env.playback.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 42, height: 42) }
                    Button { Task { await env.playback.next() } } label: { Image(systemName: "forward.end.fill").frame(width: 38, height: 42) }
                }.padding(.horizontal, 8).frame(height: 62).background(Theme.surface.opacity(0.96)).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.35))).padding(.horizontal, 10).foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var savedTracks: [SavedTrack]
    @State private var showSleepTimer = false
    @State private var backgroundAlternatives: [Track] = []
    @State private var findingAlternative = false
    let namespace: Namespace.ID
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        playerArea.frame(minHeight: 230, idealHeight: min(360, proxy.size.width * 0.72)).clipShape(RoundedRectangle(cornerRadius: 18))
                        metadata
                        backgroundOption
                        controls
                        Picker("Player section", selection: Binding(get: { env.playback.selectedPlayerTab }, set: { env.playback.selectedPlayerTab = $0 })) { Text("Up Next").tag(0); Text("Lyrics").tag(1); Text("Related").tag(2) }.pickerStyle(.segmented)
                        playerTabContent
                    }.padding(.horizontal, 18).padding(.bottom, 30)
                }
            }
            .navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { env.playback.isFullPlayerPresented = false } label: { Image(systemName: "chevron.down") } }; ToolbarItemGroup(placement: .topBarTrailing) { Button { showSleepTimer = true } label: { Image(systemName: env.playback.sleepTimerEndsAt == nil ? "moon" : "moon.fill") }; Button { toggleFavorite() } label: { Image(systemName: isFavorite ? "heart.fill" : "heart").foregroundStyle(isFavorite ? Theme.accent : .white) } } }
            .confirmationDialog("Sleep Timer", isPresented: $showSleepTimer) { Button("15 minutes") { env.playback.setSleepTimer(minutes: 15) }; Button("30 minutes") { env.playback.setSleepTimer(minutes: 30) }; Button("60 minutes") { env.playback.setSleepTimer(minutes: 60) }; if env.playback.sleepTimerEndsAt != nil { Button("Turn Off", role: .destructive) { env.playback.setSleepTimer(minutes: nil) } }; Button("Cancel", role: .cancel) {} }
            .premiumBackground()
        }
    }
    @ViewBuilder private var playerArea: some View {
        if let track = env.playback.currentTrack, track.source == .youtube || track.source == .youtubeMusic {
            YouTubePlayerView(videoID: track.videoID, provider: env.playback.youtube).overlay(alignment: .bottomLeading) { Text("YouTube · Foreground only").font(.caption.weight(.bold)).padding(8).background(.black.opacity(0.75)).clipShape(Capsule()).padding(10) }
        } else if let track = env.playback.currentTrack {
            CachedArtwork(url: track.artworkURL).matchedGeometryEffect(id: "artwork", in: namespace)
        } else { Theme.surface }
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(env.playback.currentTrack?.title ?? "Not Playing").font(.title2.bold()).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(env.playback.currentTrack?.artist ?? "").font(.body).foregroundStyle(Theme.secondary)
            Slider(value: Binding(get: { env.playback.elapsed }, set: { value in Task { await env.playback.seek(to: value) } }), in: 0...max(1, env.playback.duration)).tint(Theme.orange)
            HStack { Text(time(env.playback.elapsed)); Spacer(); Text(time(env.playback.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
    }
    private var controls: some View {
        HStack { control("shuffle", active: env.playback.isShuffled) { env.playback.toggleShuffle() }; Spacer(); control("backward.end.fill") { Task { await env.playback.previous() } }; Spacer(); Button { Task { await env.playback.toggle() } } label: { Image(systemName: env.playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 30)).frame(width: 72, height: 72).background(Theme.orange).foregroundStyle(.black).clipShape(Circle()) }; Spacer(); control("forward.end.fill") { Task { await env.playback.next() } }; Spacer(); control(env.playback.repeatMode == .one ? "repeat.1" : "repeat", active: env.playback.repeatMode != .off) { env.playback.cycleRepeat() } }
    }
    @ViewBuilder private var backgroundOption: some View {
        if let track = env.playback.currentTrack, !track.capabilities.canBackgroundPlay {
            VStack(alignment: .leading, spacing: 10) {
                Label("This YouTube result stops when the screen locks.", systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.secondary)
                if backgroundAlternatives.isEmpty { Button { Task { await findBackgroundVersion(of: track) } } label: { if findingAlternative { ProgressView() } else { Label("Find a background-capable version", systemImage: "waveform") } }.buttonStyle(.bordered).disabled(findingAlternative) }
                else { ForEach(backgroundAlternatives.prefix(3)) { alternative in TrackRow(track: alternative) { Task { await env.playback.play(alternative); backgroundAlternatives = [] } } } }
            }.padding(12).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 15))
        }
    }
    private func control(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).font(.title3).foregroundStyle(active ? Theme.orange : .white).frame(width: 40, height: 44) } }
    @ViewBuilder private var playerTabContent: some View {
        switch env.playback.selectedPlayerTab {
        case 0: LazyVStack(spacing: 8) { ForEach(Array(env.playback.queue.enumerated()), id: \.element.id) { position, track in HStack { Text("\(position + 1)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary).frame(width: 24); TrackRow(track: track) { Task { await env.playback.play(track) } }; VStack(spacing: 4) { Button { env.playback.moveQueueItem(from: position, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(position == 0); Button { env.playback.removeQueueItem(at: position) } label: { Image(systemName: "trash") }.foregroundStyle(.red) } } } }
        case 1: ContentUnavailableView("Lyrics unavailable", systemImage: "quote.bubble", description: Text("Lyrics appear only when supplied by an authorized provider."))
        default: ContentUnavailableView("Related tracks", systemImage: "sparkles", description: Text("Search for more music from this artist."))
        }
    }
    private func time(_ value: TimeInterval) -> String { let seconds = max(0, Int(value)); return String(format: "%d:%02d", seconds / 60, seconds % 60) }
    private var isFavorite: Bool { guard let id = env.playback.currentTrack?.id else { return false }; return savedTracks.first { $0.trackID == id }?.isFavorite == true }
    private func toggleFavorite() { guard let track = env.playback.currentTrack else { return }; if let saved = savedTracks.first(where: { $0.trackID == track.id }) { saved.isFavorite.toggle() } else { context.insert(SavedTrack(track: track, favorite: true)) }; try? context.save() }
    private func findBackgroundVersion(of track: Track) async { findingAlternative = true; defer { findingAlternative = false }; let provider = BackendSearchProvider(api: env.api, source: .youtubeMusic); let page = try? await provider.search(query: "\(track.title) \(track.artist)", filter: .all, pageToken: nil); backgroundAlternatives = page?.tracks.filter(\.capabilities.canBackgroundPlay) ?? [] }
}
