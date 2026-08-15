import AVFoundation
import Foundation

/// The single owner of ROZZA's process-wide AVAudioSession configuration.
///
/// Important Build 31 rule:
/// - WebKit/YouTube/HTMLAudio owns its own media playback transport.
/// - Native AVPlayer owns native playback only.
///
/// The app still configures the process category as `.playback`, but it does
/// not repeatedly force `setActive(true)` just because a YouTube frame starts.
/// Doing that created a self-interruption loop on real devices: WebKit began
/// media playback, AVAudioSession posted `.began`, and the old interruption
/// handler then paused YouTube as though the user had requested Pause.
@MainActor
final class ROZZAAudioSession {
    static let shared = ROZZAAudioSession()

    private var configured = false
    private var nativePlaybackActive = false

    private init() {}

    /// Configure category/mode once, without forcing activation. This is the
    /// correct path for WKWebView YouTube and HTMLAudio playback.
    func configureCategoryIfNeeded() throws {
        guard !configured else { return }
        let session = AVAudioSession.sharedInstance()
        print("[ROZZA AudioSession] CALL setCategory(category: playback, mode: default, options: [])")
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            configured = true
            print("[ROZZA AudioSession] OK setCategory (.playback) — activation delegated to active media owner")
        } catch {
            logFailure(api: "setCategory(.playback, mode: .default, options: [])", error: error)
            throw error
        }
    }

    /// Activate only when ROZZA's native AVPlayer is the transport owner.
    func activateForNativePlaybackIfNeeded() throws {
        try configureCategoryIfNeeded()
        guard !nativePlaybackActive else { return }
        let session = AVAudioSession.sharedInstance()
        print("[ROZZA AudioSession] CALL setActive(true) for native playback")
        do {
            try session.setActive(true, options: [])
            nativePlaybackActive = true
            print("[ROZZA AudioSession] OK setActive(true) for native playback")
        } catch {
            logFailure(api: "setActive(true, options: [])", error: error)
            throw error
        }
    }

    /// Compatibility wrapper for native-only callers. Do not call this from
    /// YouTube/WebKit paths.
    func configureAndActivateIfNeeded() throws {
        try activateForNativePlaybackIfNeeded()
    }

    func markInterrupted() { nativePlaybackActive = false }

    func reactivateNativePlaybackAfterInterruption() throws {
        try activateForNativePlaybackIfNeeded()
    }

    func printDiagnostics(prefix: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map {
            "\($0.portName) [\($0.portType.rawValue)]"
        }.joined(separator: ", ")
        print("[ROZZA AudioSession] \(prefix)")
        print("[ROZZA AudioSession] Category:", session.category.rawValue)
        print("[ROZZA AudioSession] Mode:", session.mode.rawValue)
        print("[ROZZA AudioSession] Options rawValue:", session.categoryOptions.rawValue)
        print("[ROZZA AudioSession] Output route:", outputs.isEmpty ? "none" : outputs)
        print("[ROZZA AudioSession] Sample rate:", session.sampleRate)
        print("[ROZZA AudioSession] IO buffer duration:", session.ioBufferDuration)
    }

    private func logFailure(api: String, error: Error) {
        let nsError = error as NSError
        print("[ROZZA AudioSession] FAILED API:", api)
        print("[ROZZA AudioSession] NSError domain:", nsError.domain)
        print("[ROZZA AudioSession] NSError code / OSStatus:", nsError.code)
        print("[ROZZA AudioSession] NSError description:", nsError.localizedDescription)
        print("[ROZZA AudioSession] NSError userInfo:", nsError.userInfo)
    }
}

final class SilentAudioPlayer {
    static let shared = SilentAudioPlayer()
    private var audioPlayer: AVAudioPlayer?

    private init() {
        let sampleRate: Int32 = 44100
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let numSamples = sampleRate
        let dataSize = Int32(numSamples * Int32(numChannels) * Int32(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        header.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        let fmtChunkSize: Int32 = 16
        header.append(contentsOf: withUnsafeBytes(of: fmtChunkSize.littleEndian) { Array($0) })
        let audioFormat: Int16 = 1
        header.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = numChannels * (bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        let pcmData = Data(count: Int(dataSize))
        var wavData = header
        wavData.append(pcmData)

        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.001
            audioPlayer?.prepareToPlay()
        } catch {
            print("[ROZZA SilentAudio] Failed to initialize silent audio player:", error)
        }
    }

    func play() {
        audioPlayer?.play()
    }

    func pause() {
        audioPlayer?.pause()
    }
}
