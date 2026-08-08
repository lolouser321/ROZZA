import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var env: AppEnvironment
    let onExplore: () -> Void
    let onAI: () -> Void
    let onListen: () -> Void
    @State private var egypt: [Track] = []
    @State private var global: [Track] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("ROZZA").font(.title2.weight(.black)).tracking(2)
                        Spacer()
                        Button(action: onAI) { Label("ROZZA AI", systemImage: "sparkles").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8).background(Theme.accent.opacity(0.15)).clipShape(Capsule()).overlay(Capsule().stroke(Theme.accent.opacity(0.4))) }
                    }
                    Text(greeting).font(.largeTitle.bold())
                    HStack { Button(action: onExplore) { HStack { Image(systemName: "magnifyingglass"); Text("Search music, artists…"); Spacer() }.foregroundStyle(Theme.secondary).padding(.horizontal, 16).frame(height: 48).background(.white.opacity(0.06)).clipShape(Capsule()).overlay(Capsule().stroke(.white.opacity(0.1))) }; Button(action: onListen) { Image(systemName: "mic.fill").frame(width: 48, height: 48).background(Theme.accent).foregroundStyle(.white).clipShape(Circle()) }.accessibilityLabel("Listen and identify music") }
                    if loading { LoadingSkeleton() }
                    else if let error { VStack(spacing: 12) { Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Theme.accent); Text(error).foregroundStyle(Theme.secondary); Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent) }.frame(maxWidth: .infinity).padding(.vertical, 40) }
                    else { shelf("Trending in Egypt 🇪🇬", tracks: egypt); shelf("Trending Globally", tracks: global) }
                    if !env.playback.queue.isEmpty { shelf("Recently in Queue", tracks: Array(env.playback.queue.prefix(8))) }
                }.padding(.horizontal, 20).padding(.bottom, 90)
            }.toolbar(.hidden, for: .navigationBar).task { await load() }.refreshable { await load() }.premiumBackground()
        }
    }
    private var greeting: String { let hour = Calendar.current.component(.hour, from: .now); return hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening" }
    @ViewBuilder private func shelf(_ title: String, tracks: [Track]) -> some View {
        if !tracks.isEmpty { VStack(alignment: .leading, spacing: 13) { Text(title).font(.title3.bold()); ScrollView(.horizontal, showsIndicators: false) { LazyHStack(spacing: 14) { ForEach(tracks) { track in Button { Task { await env.playback.play(track, in: tracks) } } label: { VStack(alignment: .leading, spacing: 7) { CachedArtwork(url: track.artworkURL).frame(width: 142, height: 142).clipShape(RoundedRectangle(cornerRadius: 18)); Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.white); Text(track.artist).font(.caption).lineLimit(1).foregroundStyle(Theme.secondary) }.frame(width: 142, alignment: .leading) }.buttonStyle(.plain) } } } } }
    }
    private func load() async {
        loading = true; error = nil
        do {
            let provider = BackendSearchProvider(api: env.api, source: .youtubeMusic)
            async let eg = provider.search(query: "Egyptian music", filter: .all, pageToken: nil)
            async let world = provider.search(query: "global music", filter: .all, pageToken: nil)
            egypt = Array((try await eg).tracks.prefix(10)); global = Array((try await world).tracks.prefix(10))
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct TrendingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        NavigationStack { Group {
            if loading { LoadingSkeleton().padding() }
            else if let error { ContentUnavailableView("Trending unavailable", systemImage: "exclamationmark.triangle", description: Text(error)); Button("Retry") { Task { await load() } } }
            else if tracks.isEmpty { ContentUnavailableView("No trending tracks", systemImage: "chart.line.uptrend.xyaxis", description: Text("The catalog has no current chart data.")) }
            else { ScrollView { LazyVStack(spacing: 14) { ForEach(tracks) { track in TrackRow(track: track) { Task { await env.playback.play(track, in: tracks) } } } }.padding() } }
        }.navigationTitle("Trending").task { await load() }.premiumBackground() }
    }
    private func load() async {
        loading = true; error = nil
        do { env.search.query = "Arabic music"; await env.search.search(); tracks = env.search.results; error = env.search.errorMessage }
        loading = false
    }
}

struct LibraryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedTrack.lastPlayedAt, order: .reverse) private var saved: [SavedTrack]
    @Query(sort: \SavedPlaylist.createdAt, order: .reverse) private var playlists: [SavedPlaylist]
    @State private var importing = false
    @State private var newPlaylist = false
    @State private var playlistName = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") { rows(saved.filter(\.isFavorite)) }
                Section("Recently Played") { rows(Array(saved.prefix(20))) }
                Section("Downloads") { rows(saved.filter(\.isDownloaded)) }
                Section("Playlists") {
                    ForEach(playlists) { playlist in NavigationLink(playlist.name) { Text("\(playlist.trackIDs.count) tracks").premiumBackground() } }
                    Button { newPlaylist = true } label: { Label("New Playlist", systemImage: "plus") }
                }
                Section("Local Music") { Button { importing = true } label: { Label("Import MP3 or M4A", systemImage: "square.and.arrow.down") } }
            }.scrollContentBackground(.hidden).navigationTitle("Library")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.mp3, .mpeg4Audio, .audio], allowsMultipleSelection: true) { result in importFiles(result) }
            .alert("New Playlist", isPresented: $newPlaylist) { TextField("Name", text: $playlistName); Button("Create") { let clean = playlistName.trimmingCharacters(in: .whitespaces); if !clean.isEmpty { context.insert(SavedPlaylist(name: clean)); try? context.save() }; playlistName = "" }; Button("Cancel", role: .cancel) {} }
            .premiumBackground()
        }
    }
    @ViewBuilder private func rows(_ entries: [SavedTrack]) -> some View {
        if entries.isEmpty { Text("Nothing here yet").foregroundStyle(Theme.secondary) }
        ForEach(entries) { entry in if let track = entry.track { TrackRow(track: track) { Task { await env.playback.play(track) } } } }
    }
    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for original in urls {
            guard original.startAccessingSecurityScopedResource() else { continue }
            defer { original.stopAccessingSecurityScopedResource() }
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "ImportedMusic", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appending(path: "\(UUID().uuidString)-\(original.lastPathComponent)")
            do { try FileManager.default.copyItem(at: original, to: destination); Task { let track = await LocalMetadataReader.track(for: destination); context.insert(SavedTrack(track: track, favorite: false, downloaded: true)); try? context.save() } } catch { continue }
        }
    }
}

struct AccountView: View {
    @EnvironmentObject private var env: AppEnvironment
    @AppStorage("rozza.highQuality") private var highQuality = true
    @AppStorage("rozza.offlineOnly") private var offlineOnly = false
    @AppStorage("rozza.aiPersonalization") private var personalization = true
    @AppStorage("rozza.discoveryNotifications") private var notifications = true
    var body: some View {
        NavigationStack {
            List {
                Section { HStack(spacing: 15) { ZStack { Circle().fill(LinearGradient(colors: [Theme.accent, Theme.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)); Text("R").font(.title.bold()) }.frame(width: 62, height: 62); VStack(alignment: .leading) { Text("ROZZA Listener").font(.headline); Text("iPhone Premium Edition").font(.caption).foregroundStyle(Theme.accent) } } }
                MusicSourceSettings()
                Section("PLAYBACK & AUDIO") { Toggle("High Quality Streaming", isOn: $highQuality); Toggle("Offline Mode Only", isOn: $offlineOnly); Label("Native background audio enabled", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.cyan); Label("YouTube is foreground only", systemImage: "play.rectangle.fill").foregroundStyle(Theme.secondary) }
                Section("ROZZA AI INTELLIGENCE") { Toggle("Realtime Taste Learning", isOn: $personalization) }
                Section("NOTIFICATIONS") { Toggle("Music Discovery Alerts", isOn: $notifications) }
                Section("SERVICE") { LabeledContent("Backend", value: env.configuration.apiBaseURL.host ?? "Not configured"); LabeledContent("Version", value: "1.0.0"); LabeledContent("Architecture", value: "Native SwiftUI") }
                Section("PRIVACY") { Text("Provider credentials remain on the ROZZA backend. The app never asks listeners for API keys.") }
            }.scrollContentBackground(.hidden).navigationTitle("Account & Settings").premiumBackground()
        }
    }
}
