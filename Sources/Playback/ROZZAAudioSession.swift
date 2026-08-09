import AVFoundation
import Foundation

/// The single owner of ROZZA's process-wide AVAudioSession configuration.
/// Category and mode are set at most once; callers may request reactivation
/// after an interruption without changing the configuration.
@MainActor
final class ROZZAAudioSession {
    static let shared = ROZZAAudioSession()

    private var configured = false
    private var active = false

    private init() {}

    func configureAndActivateIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()

        if !configured {
            print("[ROZZA AudioSession] CALL setCategory(category: playback, mode: default, options: [])")
            do {
                // The playback category already supports Bluetooth A2DP and
                // AirPlay routing. Passing record-oriented Bluetooth options
                // here can produce an incompatible-category OSStatus error.
                try session.setCategory(.playback, mode: .default, options: [])
                configured = true
                print("[ROZZA AudioSession] OK setCategory (.playback)")
            } catch {
                logFailure(api: "setCategory(.playback, mode: .default, options: [])", error: error)
                throw error
            }
        } else {
            print("[ROZZA AudioSession] SKIP setCategory — already configured once")
        }

        if !active {
            print("[ROZZA AudioSession] CALL setActive(true), options: [] / rawValue: 0")
            do {
                try session.setActive(true, options: [])
                active = true
                // SilentAudioPlayer.shared.play() removed from this path.
                // A near-silent infinite AVAudioPlayer loop was started on
                // every session activation, including for YouTube — but real
                // audio sources (AVPlayer, local files) generate real audio
                // and need no keepalive, and YouTube's embed is foreground-
                // only for now, so nothing in the current playback path needs
                // a second audio player running underneath it. If background
                // YouTube is tackled later and something like this proves
                // genuinely necessary, reintroduce it deliberately then, not
                // as a leftover from an earlier workaround attempt.
                print("[ROZZA AudioSession] OK setActive(true)")
            } catch {
                logFailure(api: "setActive(true, options: [])", error: error)
                throw error
            }
        }

        printDiagnostics(prefix: "activated")
    }

    /// Interruption end may require activation again, but never reconfigures
    /// the category, mode, or options.
    func markInterrupted() { active = false }

    func reactivateAfterInterruption() throws {
        try configureAndActivateIfNeeded()
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
