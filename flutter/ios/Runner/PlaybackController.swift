import AVFoundation
import MediaPlayer

private struct NativeTrack {
  let id: String
  let title: String
  let artist: String
  let album: String
  let artworkURL: String
  let durationMs: Int
  let audioURL: String?
  let accent: Int

  init?(_ map: [String: Any]) {
    guard let id = map["id"] as? String else { return nil }
    self.id = id
    title = map["title"] as? String ?? "Untitled"
    artist = map["artist"] as? String ?? "ROZZA"
    album = map["album"] as? String ?? ""
    artworkURL = map["artworkUrl"] as? String ?? ""
    durationMs = (map["durationMs"] as? NSNumber)?.intValue ?? 0
    audioURL = map["audioUrl"] as? String
    accent = (map["accent"] as? NSNumber)?.intValue ?? 0xFFFF3D79
  }

  var dictionary: [String: Any] {
    [
      "id": id, "title": title, "artist": artist, "album": album,
      "artworkUrl": artworkURL, "durationMs": durationMs,
      "audioUrl": audioURL ?? "", "accent": accent,
    ]
  }
}

private enum NativeTransportCommand: String {
  case play, pause, toggle, next, previous
}

/// The future Flutter app's single iOS playback state machine. Flutter sends
/// user requests and renders emitted state; it never owns MPRemoteCommandCenter.
final class NativePlaybackController {
  static let shared = NativePlaybackController()

  var eventHandler: (([String: Any]) -> Void)?

  private let player = AVPlayer()
  private var queue: [NativeTrack] = []
  private var queueIndex = -1
  private var status = "paused"
  private var positionMs = 0
  private var wantPlay = false
  private var humanPauseActive = true
  private var transportGeneration = 0
  private var commandSequence = 0

  private init() {
    configureAudioSession()
    configureRemoteCommands()
  }

  func setQueue(_ maps: [[String: Any]], startIndex: Int) {
    queue = maps.compactMap(NativeTrack.init)
    queueIndex = queue.isEmpty ? -1 : min(max(startIndex, 0), queue.count - 1)
    positionMs = 0
    prepareCurrentTrack(autoplay: false)
    emit("queueChanged")
  }

  func loadTrack(_ map: [String: Any], autoplay: Bool) {
    guard let track = NativeTrack(map) else { return }
    if let index = queue.firstIndex(where: { $0.id == track.id }) {
      queueIndex = index
    } else {
      queue.append(track)
      queueIndex = queue.count - 1
    }
    transportGeneration += 1
    positionMs = 0
    humanPauseActive = !autoplay
    wantPlay = autoplay
    prepareCurrentTrack(autoplay: autoplay)
    emit("currentTrackChanged")
  }

  func play(sourceChannel: String = "flutter-ui") {
    transportGeneration += 1
    humanPauseActive = false
    wantPlay = true
    activateAudioSession()
    if player.currentItem == nil { prepareCurrentTrack(autoplay: true) }
    player.play()
    status = "playing"
    updateNowPlaying()
    emit("playbackStateChanged")
  }

  func pause(sourceChannel: String = "flutter-ui") {
    transportGeneration += 1
    humanPauseActive = true
    wantPlay = false
    player.pause()
    status = "paused"
    updateNowPlaying()
    emit("playbackStateChanged")
  }

  @discardableResult
  func next(sourceChannel: String = "flutter-ui") -> Bool {
    guard queueIndex + 1 < queue.count else { return false }
    transportGeneration += 1
    queueIndex += 1 // exactly one queue mutation per accepted command
    positionMs = 0
    humanPauseActive = false
    wantPlay = true
    prepareCurrentTrack(autoplay: true)
    emit("currentTrackChanged")
    return true
  }

  @discardableResult
  func previous(sourceChannel: String = "flutter-ui") -> Bool {
    guard queueIndex > 0 else { return false }
    transportGeneration += 1
    queueIndex -= 1 // exactly one queue mutation per accepted command
    positionMs = 0
    humanPauseActive = false
    wantPlay = true
    prepareCurrentTrack(autoplay: true)
    emit("currentTrackChanged")
    return true
  }

  func seek(positionMs: Int) {
    self.positionMs = max(0, positionMs)
    player.seek(to: CMTime(value: CMTimeValue(self.positionMs), timescale: 1000))
    updateNowPlaying()
    emit("playbackStateChanged")
  }

  func snapshot() -> [String: Any] {
    [
      "status": status,
      "queue": queue.map(\.dictionary),
      "queueIndex": queueIndex,
      "positionMs": positionMs,
      "wantPlay": wantPlay,
      "humanPauseActive": humanPauseActive,
      "generation": transportGeneration,
    ]
  }

  private func prepareCurrentTrack(autoplay: Bool) {
    guard queue.indices.contains(queueIndex) else {
      player.replaceCurrentItem(with: nil)
      status = "idle"
      updateNowPlaying()
      return
    }
    let track = queue[queueIndex]
    if let rawURL = track.audioURL, let url = URL(string: rawURL) {
      player.replaceCurrentItem(with: AVPlayerItem(url: url))
    } else {
      // Phase 1 mock/YouTube entries intentionally have no native audio URL.
      player.replaceCurrentItem(with: nil)
    }
    if autoplay {
      activateAudioSession()
      player.play()
      status = "playing"
    } else {
      player.pause()
      status = "paused"
    }
    updateNowPlaying()
  }

  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .default,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
    } catch {
      emitError("audio-session-config", error: error)
    }
  }

  private func activateAudioSession() {
    do { try AVAudioSession.sharedInstance().setActive(true) }
    catch { emitError("audio-session-activation", error: error) }
  }

  private func updateNowPlaying() {
    guard queue.indices.contains(queueIndex) else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    let track = queue[queueIndex]
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPMediaItemPropertyPlaybackDuration: Double(track.durationMs) / 1000,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
      MPNowPlayingInfoPropertyPlaybackRate: wantPlay ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
      MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
    ]
  }

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
     center.nextTrackCommand, center.previousTrackCommand,
     center.skipForwardCommand, center.skipBackwardCommand,
     center.changePlaybackPositionCommand].forEach { $0.removeTarget(nil) }

    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.nextTrackCommand.isEnabled = true
    center.previousTrackCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = false
    center.skipBackwardCommand.isEnabled = false
    center.changePlaybackPositionCommand.isEnabled = false

    center.playCommand.addTarget { [weak self] _ in self?.remote(.play) ?? .commandFailed }
    center.pauseCommand.addTarget { [weak self] _ in self?.remote(.pause) ?? .commandFailed }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.remote(.toggle) ?? .commandFailed }
    center.nextTrackCommand.addTarget { [weak self] _ in self?.remote(.next) ?? .commandFailed }
    center.previousTrackCommand.addTarget { [weak self] _ in self?.remote(.previous) ?? .commandFailed }
  }

  private func remote(_ command: NativeTransportCommand) -> MPRemoteCommandHandlerStatus {
    commandSequence += 1
    let commandID = commandSequence
    let before = queueIndex
    let accepted: Bool
    switch command {
    case .play: play(sourceChannel: "mp-remote-command-center"); accepted = true
    case .pause: pause(sourceChannel: "mp-remote-command-center"); accepted = true
    case .toggle:
      if wantPlay { pause(sourceChannel: "mp-remote-command-center") }
      else { play(sourceChannel: "mp-remote-command-center") }
      accepted = true
    case .next: accepted = next(sourceChannel: "mp-remote-command-center")
    case .previous: accepted = previous(sourceChannel: "mp-remote-command-center")
    }
    let videoID = queue.indices.contains(queueIndex) ? queue[queueIndex].id : "none"
    let rejectionReason = accepted ? "none" : "queue-boundary"
    print("[ROZZA REMOTE] \(command.rawValue.uppercased()) sourceChannel=mp-remote-command-center commandID=\(commandID) queueIndexBefore=\(before) queueIndexAfter=\(queueIndex) videoId=\(videoID) wantPlay=\(wantPlay) humanPauseActive=\(humanPauseActive) accepted=\(accepted) rejectionReason=\(rejectionReason)")
    emit("remoteCommandReceived", extra: [
      "command": command.rawValue, "sourceChannel": "mp-remote-command-center",
      "commandID": commandID, "queueIndexBefore": before,
      "queueIndexAfter": queueIndex, "accepted": accepted,
      "rejectionReason": rejectionReason,
    ])
    return accepted ? .success : .noSuchContent
  }

  private func emit(_ name: String, extra: [String: Any] = [:]) {
    var event: [String: Any] = ["event": name, "state": snapshot()]
    extra.forEach { event[$0.key] = $0.value }
    DispatchQueue.main.async { [weak self] in self?.eventHandler?(event) }
  }

  private func emitError(_ code: String, error: Error) {
    emit("error", extra: ["code": code, "message": error.localizedDescription])
  }
}
