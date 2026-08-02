import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var env: AppEnvironment
    let onAI: () -> Void
    let onListen: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchField
                    suggestions
                    Picker("Source", selection: Binding(get: { env.search.source }, set: { env.search.source = $0 })) {
                        Text("YouTube Music").tag(ContentSource.youtubeMusic)
                        Text("YouTube").tag(ContentSource.youtube)
                    }
                    .pickerStyle(.segmented)
                    .frame(height: 38)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(SearchFilter.allCases) { filter in
                                Button(filter.title) {
                                    env.search.filter = filter
                                    if !env.search.query.isEmpty { Task { await env.search.search() } }
                                }
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 17)
                                .frame(height: 42)
                                .background(env.search.filter == filter ? Theme.accent : Theme.elevated)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    if env.search.isLoading { LoadingSkeleton() }
                    else if let message = env.search.errorMessage { ContentUnavailableView("Couldn’t load music", systemImage: "wifi.exclamationmark", description: Text(message)); Button("Retry") { Task { await env.search.search() } }.buttonStyle(.borderedProminent) }
                    else if env.search.results.isEmpty { emptyState }
                    else { LazyVStack(spacing: 14) { ForEach(env.search.results) { track in TrackRow(track: track) { Task { await env.playback.play(track, in: env.search.results) } } } } }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .premiumBackground()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Explore")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Spacer()
            HStack(spacing: 4) {
                Button(action: onListen) { Image(systemName: "mic.fill").frame(width: 38, height: 38) }
                Button(action: onAI) { Image(systemName: "sparkles").frame(width: 38, height: 38) }
            }
            .foregroundStyle(Theme.accent)
            .background(Theme.elevated)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.accent.opacity(0.25)))
        }
    }

    private var searchField: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(Theme.secondary)
            TextField("Songs, artists, playlists", text: Binding(get: { env.search.query }, set: { env.search.query = $0 }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await env.search.search() } }
                .onChange(of: env.search.query) { _, _ in env.search.queryChanged() }
            if !env.search.query.isEmpty {
                Button { env.search.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondary) }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var suggestions: some View {
        if !env.search.query.isEmpty && !env.search.suggestions.isEmpty && env.search.results.isEmpty {
            VStack(spacing: 0) {
                ForEach(env.search.suggestions.prefix(5), id: \.self) { value in
                    Button { env.search.use(value) } label: {
                        HStack { Image(systemName: "magnifyingglass"); Text(value).lineLimit(1); Spacer() }
                            .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    @ViewBuilder private var emptyState: some View {
        if env.search.query.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Recent Searches").font(.headline); Spacer(); if !env.search.recentSearches.isEmpty { Button("Clear") { env.search.clearRecent() }.font(.caption) } }
                ForEach(env.search.recentSearches, id: \.self) { term in Button { env.search.use(term) } label: { Label(term, systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).padding(.vertical, 5) }
            }
        } else { ContentUnavailableView("No results", systemImage: "music.note.list", description: Text("Try another title, artist, or filter.")) }
    }
}
