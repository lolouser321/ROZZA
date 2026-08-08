import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class RecognitionViewModel: NSObject, ObservableObject {
    enum State { case idle, permission, listening, processing, found, notFound, failed }
    @Published var state: State = .idle
    @Published var result: Track?
    @Published var errorMessage = ""
    private var recorder: AVAudioRecorder?

    func start(api: APIClient) async {
        state = .permission; result = nil; errorMessage = ""
        let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        guard granted else { state = .failed; errorMessage = "Microphone access is required for Listen."; return }
        do {
            // Recognition must never reconfigure or deactivate the shared
            // playback session. The recorder either starts under the existing
            // session or fails cleanly without disrupting active decks.
            try ROZZAAudioSession.shared.configureAndActivateIfNeeded()
            let url = FileManager.default.temporaryDirectory.appending(path: "rozza-listen-\(UUID().uuidString).m4a")
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]); recorder?.record(); state = .listening
            try await Task.sleep(for: .seconds(8)); guard state == .listening else { return }; recorder?.stop(); state = .processing
            let data = try await api.uploadAudio(url)
            struct Response: Decodable { let found: Bool; let track: DTO?; struct DTO: Decodable { let title, artist: String?; let album, artwork, youtubeVideoId, previewUrl: String? } }
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.found, let dto = response.track else { state = .notFound; return }
            let native = dto.previewUrl.flatMap(URL.init(string:))
            result = Track(id: "recognized-\(UUID().uuidString)", title: dto.title ?? "Unknown", artist: dto.artist ?? "Unknown", artworkURL: dto.artwork.flatMap(URL.init(string:)), duration: 0, source: native == nil ? .youtube : .licensed, kind: native == nil ? .video : .song, playbackURL: native, videoID: native == nil ? dto.youtubeVideoId : nil, capabilities: native == nil ? .youtube : .nativeStream); state = .found
        } catch { state = .failed; errorMessage = error.localizedDescription }
    }
    func cancel() { recorder?.stop(); recorder = nil; state = .idle }
}

struct ListenRecognitionView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = RecognitionViewModel()
    let api: APIClient
    var body: some View {
        NavigationStack { VStack(spacing: 22) { Spacer()
            switch model.state {
            case .idle: Text("Tap to identify music playing around you").foregroundStyle(Theme.secondary); microphone
            case .permission: ProgressView("Requesting microphone access…")
            case .listening: Image(systemName: "waveform").font(.system(size: 64)).foregroundStyle(Theme.cyan).symbolEffect(.variableColor.iterative); Text("Listening for music…").font(.title2.bold()); Button("Cancel") { model.cancel() }
            case .processing: ProgressView("Recognizing with AudD…").tint(Theme.accent)
            case .found: Image(systemName: "checkmark.circle.fill").font(.system(size: 58)).foregroundStyle(Theme.cyan); Text(model.result?.title ?? "Music recognized").font(.title2.bold()); Text(model.result?.artist ?? "").foregroundStyle(Theme.secondary); if let track = model.result { Button("Play on ROZZA") { Task { await env.playback.play(track); dismiss() } }.buttonStyle(.borderedProminent).tint(Theme.accent) }
            case .notFound: ContentUnavailableView("No match found", systemImage: "waveform.badge.magnifyingglass", description: Text("Move closer to the music and try again.")); Button("Try Again") { Task { await model.start(api: api) } }
            case .failed: ContentUnavailableView("Listen unavailable", systemImage: "exclamationmark.triangle", description: Text(model.errorMessage)); Button("Try Again") { Task { await model.start(api: api) } }
            }
            Spacer()
        }.padding().navigationTitle("ROZZA Listen").toolbar { Button("Done") { model.cancel(); dismiss() } }.premiumBackground() }
    }
    private var microphone: some View { Button { Task { await model.start(api: api) } } label: { Image(systemName: "mic.fill").font(.system(size: 48)).frame(width: 180, height: 180).background(Theme.accent.opacity(0.2)).clipShape(Circle()).overlay(Circle().stroke(Theme.accent, lineWidth: 2)) }.buttonStyle(.plain) }
}
