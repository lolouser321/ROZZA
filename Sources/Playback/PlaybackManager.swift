import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class PlaybackManager: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var queue: [Track] = []
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffled = false
    @Published var isFullPlayerPresented = false
    @Published var selectedPlayerTab = 0
    @Published private(set) var sleepTimerEndsAt: Date?
    @Published var foregroundOnlyNotice: Track?

    let youtube = YouTubeEmbeddedProvider()
    private let local = LocalAudioProvider()
    private let licensed = LicensedCatalogProvider()
    private var provider: PlaybackProvider?
    private var timer: Timer?
    private var sleepTimer: Timer?
    private var index = 0

    init() { configureRemoteCommands(); restore() }

    func play(_ track: Track, in tracks: [Track]? = nil) async {
        if let tracks { queue = tracks; index = tracks.firstIndex(of: track) ?? 0 }
        else if let found = queue.firstIndex(of: track) { index = found } else { queue.append(track); index = queue.count - 1 }
        provider?.stop()
        provider = providerFor(track)
        do {
            try await provider?.load(track)
            try await provider?.play()
            currentTrack = track; duration = track.duration; elapsed = 0; isPlaying = true
            if !track.capabilities.canBackgroundPlay { foregroundOnlyNotice = track }
            if track.capabilities.supportsLockScreen { updateNowPlaying() } else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
            beginProgressUpdates(); persist()
        } catch { isPlaying = false }
    }

    func toggle() async {
        guard provider != nil else { return }
        if isPlaying { provider?.pause(); isPlaying = false }
        else { try? await provider?.play(); isPlaying = true }
        updateNowPlaying(); persist()
    }
    func next() async {
        guard !queue.isEmpty else { return }
        if isShuffled { index = Int.random(in: queue.indices) }
        else if index + 1 < queue.count { index += 1 }
        else if repeatMode == .all { index = 0 } else { isPlaying = false; return }
        await play(queue[index])
    }
    func previous() async { guard !queue.isEmpty else { return }; index = index > 0 ? index - 1 : max(0, queue.count - 1); await play(queue[index]) }
    func seek(to seconds: TimeInterval) async { elapsed = seconds; await provider?.seek(to: seconds); updateNowPlaying() }
    func cycleRepeat() { repeatMode = repeatMode == .off ? .all : repeatMode == .all ? .one : .off; persist() }
    func toggleShuffle() { isShuffled.toggle(); persist() }
    func addToQueue(_ track: Track) { if !queue.contains(track) { queue.append(track); persist() } }
    func playNext(_ track: Track) { let position = min(index + 1, queue.count); queue.insert(track, at: position); persist() }
    func stop() { provider?.pause(); isPlaying = false; setSleepTimer(minutes: nil); updateNowPlaying(); persist() }
    func removeFromQueue(at offsets: IndexSet) { queue.remove(atOffsets: offsets); index = min(index, max(0, queue.count - 1)); persist() }
    func moveQueue(from offsets: IndexSet, to destination: Int) { queue.move(fromOffsets: offsets, toOffset: destination); index = currentTrack.flatMap { queue.firstIndex(of: $0) } ?? 0; persist() }
    func removeQueueItem(at position: Int) { guard queue.indices.contains(position) else { return }; queue.remove(at: position); index = currentTrack.flatMap { queue.firstIndex(of: $0) } ?? 0; persist() }
    func moveQueueItem(from: Int, by delta: Int) { let target = from + delta; guard queue.indices.contains(from), queue.indices.contains(target) else { return }; queue.swapAt(from, target); index = currentTrack.flatMap { queue.firstIndex(of: $0) } ?? 0; persist() }
    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate(); sleepTimer = nil; sleepTimerEndsAt = nil
        guard let minutes else { return }
        sleepTimerEndsAt = Date().addingTimeInterval(Double(minutes * 60))
        sleepTimer = .scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in Task { @MainActor in self?.provider?.pause(); self?.isPlaying = false; self?.sleepTimerEndsAt = nil; self?.updateNowPlaying() } }
    }

    private func providerFor(_ track: Track) -> PlaybackProvider {
        switch track.source { case .youtube, .youtubeMusic: youtube; case .local: local; case .licensed: licensed }
    }
    private func beginProgressUpdates() {
        timer?.invalidate()
        timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self, self.isPlaying else { return }; self.elapsed += 1; self.updateNowPlaying() }
        }
    }
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in Task { await self?.toggle() }; return .success }
        center.pauseCommand.addTarget { [weak self] _ in Task { await self?.toggle() }; return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in Task { await self?.next() }; return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in Task { await self?.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { await self?.seek(to: position.positionTime) }; return .success
        }
    }
    private func updateNowPlaying() {
        guard let track = currentTrack, track.capabilities.supportsLockScreen else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0]
    }
    private func persist() {
        let state = PlayerState(track: currentTrack, queue: queue, index: index, elapsed: elapsed, repeatMode: repeatMode, shuffled: isShuffled)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: "rozza.player") }
    }
    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: "rozza.player"), let state = try? JSONDecoder().decode(PlayerState.self, from: data) else { return }
        currentTrack = state.track; queue = state.queue; index = min(state.index, max(0, state.queue.count - 1)); elapsed = state.elapsed; duration = state.track?.duration ?? 0; repeatMode = state.repeatMode; isShuffled = state.shuffled
    }
}

private struct PlayerState: Codable { let track: Track?; let queue: [Track]; let index: Int; let elapsed: TimeInterval; let repeatMode: RepeatMode; let shuffled: Bool }
